--- @class jj.file
local M = {}

local runner = require("jj.core.runner")
local buffer = require("jj.core.buffer")
local utils = require("jj.utils")
local parser = require("jj.core.parser")

--- @class jj.file.read_target_opts
--- @field rev? string Revision to read the file from
--- @field path? string Path to the file (`%`, absolute, or repository-relative)

--- @class jj.file.open_target_opts
--- @field rev? string Revision to open the file from
--- @field path? string Path to the file (`%`, absolute, or repository-relative)
--- @field split? "horizontal"|"vertical"|"tab"|"current" Open in split direction (default: "current")

--- Fetch file content from jj synchronously.
--- Returns lines with blank lines preserved; trailing empty line removed.
--- @param rev string The revision (change ID or other revset)
--- @param path string Repository-relative path
--- @return string[] lines
--- @return boolean had_eol Whether the content had a trailing newline
local function get_file_content(rev, path)
	local content, ok = runner.execute_command(
		string.format("jj file show -r %s %s", vim.fn.shellescape(rev), vim.fn.shellescape(path)),
		nil,
		nil,
		true
	)
	if not ok or not content then
		return {}, false
	end
	local lines = vim.split(content, "\n", { plain = true, trimempty = false })
	local had_eol = #lines > 0 and lines[#lines] == ""
	if had_eol then
		table.remove(lines, #lines)
	end
	return lines, had_eol
end
M.get_file_content = get_file_content

--- Reads a target file revision into the current buffer (undoable).
--- @param opts? jj.file.read_target_opts
function M.read_target(opts)
	local revision = opts and opts.rev or "@"
	local raw_path = opts and opts.path or "%"
	local path, normalize_err = utils.normalize_repo_path(raw_path)
	if not path then
		utils.notify(normalize_err or "Could not normalize path", vim.log.levels.ERROR)
		return
	end

	local buf = vim.api.nvim_get_current_buf()
	local cmd = string.format("jj file show -r %s %s", vim.fn.shellescape(revision), vim.fn.shellescape(path))
	runner.execute_command_async(cmd, function(out)
		local lines = vim.split(out, "\n", { plain = true, trimempty = false })
		if #lines > 0 and lines[#lines] == "" then
			table.remove(lines, #lines)
		end
		if vim.bo[buf].modifiable == false then
			utils.notify("Current buffer is not modifiable", vim.log.levels.ERROR)
			return
		end
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].modified = true
	end, string.format("Could not read `%s` from `%s`", path, revision))
end

--- Write buffer content back into a jj revision, bypassing the working copy.
--- @param buf integer
--- @param change_id string
--- @param rel_path string Repository-relative path of the file
local function write_revision_file(buf, change_id, rel_path)
	if utils.is_change_immutable(change_id) then
		utils.notify("Cannot write to immutable revision: " .. change_id, vim.log.levels.ERROR)
		return
	end

	local new_content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
	if vim.bo[buf].eol then
		new_content = new_content .. "\n"
	end

	local tmp = vim.fn.tempname()
	local cf = io.open(tmp, "w")
	if not cf then
		utils.notify("Failed to create temp file", vim.log.levels.ERROR)
		return
	end
	cf:write(new_content)
	cf:close()

	-- Configure `cp` as the diffedit tool inline via --config.
	-- jj expands $right to the directory it populates with <rev>'s content,
	-- so the parent directory for rel_path already exists there.
	local prog_config = 'merge-tools.jj-nvim-write.program="cp"'
	-- json_encode produces valid TOML inline arrays.
	local args_config = "merge-tools.jj-nvim-write.edit-args="
		.. vim.fn.json_encode({ tmp, "$right/" .. rel_path })

	local _, ok = runner.execute_command(
		string.format(
			"jj diffedit --from 'root()' --to %s --config %s --config %s --tool jj-nvim-write -- %s",
			vim.fn.shellescape(change_id),
			vim.fn.shellescape(prog_config),
			vim.fn.shellescape(args_config),
			vim.fn.shellescape(rel_path)
		),
		"jj: failed to edit revision"
	)

	os.remove(tmp)

	if not ok then return end
	vim.bo[buf].modified = false
	utils.notify(string.format("Written to revision %s", change_id))
end
M.write_revision_file = write_revision_file

--- Opens a target file revision in a new buffer.
--- @param opts jj.file.open_target_opts
function M.open_target(opts)
	local revision = opts.rev or "@"
	local raw_path = opts.path or "%"
	local path, normalize_err = utils.normalize_repo_path(raw_path)
	if not path then
		utils.notify(normalize_err or "Could not normalize path", vim.log.levels.ERROR)
		return
	end

	local raw_ids, ok = runner.execute_command(
		string.format([[jj log --no-graph -r %s -T 'change_id ++ "\n"' --quiet]], vim.fn.shellescape(revision)),
		"jj: failed to resolve revision",
		nil,
		true
	)
	if not ok then return end
	local ids = vim.split(vim.trim(raw_ids), "\n", { trimempty = true })
	if #ids ~= 1 then
		utils.notify(string.format("Revision '%s' is ambiguous", revision), vim.log.levels.ERROR)
		return
	end
	local change_id = ids[1]

	local lines, had_eol = get_file_content(change_id, path)
	local ft = vim.filetype.match({ filename = path })

	local buf, _ = buffer.create({
		name = string.format("jj://%s/%s", change_id, path),
		split = opts.split or "current",
		modifiable = true,
		buftype = "acwrite",
		bufhidden = "wipe",
		filetype = ft,
	})
	vim.bo[buf].buflisted = true
	vim.bo[buf].swapfile = false
	local ul = vim.bo[buf].undolevels
	vim.bo[buf].undolevels = -1
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].undolevels = ul
	vim.bo[buf].eol = had_eol

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = buf,
		callback = function()
			write_revision_file(buf, change_id, path)
		end,
	})

	vim.bo[buf].modified = false
end

--- Complete `<rev>:<file>` arguments for file commands.
--- @param arglead string
--- @return string[]
local function complete_target(arglead)
	local rev, file_prefix = arglead:match("^([^:]+):(.*)$")
	if not rev then
		return {}
	end

	local out, ok = runner.execute_command(
		string.format("jj file list -r %s", vim.fn.shellescape(rev)),
		nil,
		nil,
		true
	)
	if not ok or not out then
		return {}
	end

	local items = {}
	local seen = {}
	for line in out:gmatch("[^\r\n]+") do
		local file = vim.trim(line)
		if file ~= "" and vim.startswith(file, file_prefix) then
			local candidate = rev .. ":" .. file
			if not seen[candidate] then
				table.insert(items, candidate)
				seen[candidate] = true
			end
		end
	end
	return items
end

function M.register_command()
	-- Allow :e on jj:// buffers to reload their content.
	vim.api.nvim_create_autocmd("BufReadCmd", {
		pattern = "jj://*",
		nested = true,
		callback = function()
			local name = vim.api.nvim_buf_get_name(0)
			local change_id, path = utils.parse_jj_uri(name)
			if not change_id then return end
			local lines, had_eol = get_file_content(change_id, path)
			local buf = vim.api.nvim_get_current_buf()
			vim.bo[buf].modifiable = true
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
			vim.bo[buf].eol = had_eol
			vim.bo[buf].modified = false
			vim.bo[buf].modifiable = false
			vim.api.nvim_exec_autocmds("BufReadPost", { buffer = buf })
		end,
	})

	vim.api.nvim_create_user_command("Jread", function(opts)
		local parsed = parser.parse_file_module_input(opts.args)
		M.read_target({
			rev = parsed and parsed.rev,
			path = parsed and parsed.path,
		})
	end, {
		desc = "Read a jj file revision into the current buffer",
		nargs = "?",
		complete = function(arglead, _, _)
			return complete_target(arglead)
		end,
	})

	local function create_open_command(name, split, desc)
		vim.api.nvim_create_user_command(name, function(opts)
			local parsed = parser.parse_file_module_input(opts.args)
			M.open_target({
				rev = parsed and parsed.rev,
				path = parsed and parsed.path,
				split = split,
			})
		end, {
			desc = desc,
			nargs = "?",
			complete = function(arglead, _, _)
				return complete_target(arglead)
			end,
		})
	end

	create_open_command("Jedit", "current", "Open a jj file revision in the current window")
	create_open_command("Jtabedit", "tab", "Open a jj file revision in a new tab")
	create_open_command("Jsplit", "horizontal", "Open a jj file revision in a horizontal split")
	create_open_command("Jvsplit", "vertical", "Open a jj file revision in a vertical split")
end

return M
