--- @class jj.file
local M = {}

local runner = require("jj.core.runner")
local buffer = require("jj.core.buffer")
local utils = require("jj.utils")
local parser = require("jj.core.parser")

--- @class jj.file.read_target_opts
--- @field rev string|nil Revision to read the file from
--- @field path? string|nil Path to the file (`%`, absolute, or repository-relative)

--- @class jj.file.open_target_opts
--- @field rev string|nil Revision to open the file from
--- @field path string|nil Path to the file (`%`, absolute, or repository-relative)
--- @field split "horizontal"|"vertical"|"tab" Open in split direction (default: "tab")

--- Reads a target file revision into the current buffer (undoable)
--- @param opts? jj.file.read_target_opts Options for reading the target file
function M.read_target(opts)
	local revision = opts and opts.rev or "@"
	local raw_path = opts and opts.path or "%"
	local path, normalize_err = utils.normalize_repo_path(raw_path)
	if not path then
		utils.notify(normalize_err or "Could not normalize path", vim.log.levels.ERROR)
		return
	end

	local cmd = string.format("jj file show -r %s %s", vim.fn.shellescape(revision), vim.fn.shellescape(path))
	runner.execute_command_async(cmd, function(out)
		-- Preserve blank lines exactly; only drop the final trailing newline artifact.
		local lines = vim.split(out, "\n", { plain = true, trimempty = false })
		if #lines > 0 and lines[#lines] == "" then
			table.remove(lines, #lines)
		end
		local buf = vim.api.nvim_get_current_buf()

		if vim.bo[buf].modifiable == false then
			utils.notify("Current buffer is not modifiable", vim.log.levels.ERROR)
			return
		end

		-- Set the buffer content to the file content
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].modified = true
	end, string.format("Could not open `%s` from `%s` to read it in the current buffer", path, revision), nil, nil, nil)
end

--- Opens a target file revision in a new buffer
--- @param opts jj.file.open_target_opts Options for opening the target file
function M.open_target(opts)
	local revision = opts.rev or "@"
	local raw_path = opts.path or "%"
	local path, normalize_err = utils.normalize_repo_path(raw_path)
	if not path then
		utils.notify(normalize_err or "Could not normalize path", vim.log.levels.ERROR)
		return
	end
	-- Get the actual change id instead fo working directly with the revset
	local change_id = utils.get_revision_change(revision)
	if not change_id then
		return
	end

	local ft = vim.filetype.match({ filename = path })
	local cmd = string.format("jj file show -r %s %s", vim.fn.shellescape(revision), vim.fn.shellescape(path))

	runner.execute_command_async(cmd, function(out)
		local buf, _ = buffer.create({
			name = string.format("jj://%s/%s", change_id, path),
			split = opts.split or "tab",
			modifiable = true,
			buftype = "nofile",
			bufhidden = "wipe",
			filetype = ft,
		})
		-- Actually want to list the file
		vim.bo[buf].buflisted = true
		-- Preserve blank lines exactly; only drop the final trailing newline artifact.
		local lines = vim.split(out, "\n", { plain = true, trimempty = false })
		if #lines > 0 and lines[#lines] == "" then
			table.remove(lines, #lines)
		end

		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].modified = false
		buffer.set_modifiable(buf, false)
	end, string.format("Could not open edit file `%s` from `%s`", path, revision), nil, nil, nil)
end

--- Complete `Jread` target arguments for the `<rev>:<file>` form.
---
--- This completion intentionally focuses on the file segment (after `:`).
--- The revision segment is parsed only to run `jj file list -r <rev>`.
---
--- @param arglead string Current argument text being completed by cmdline
--- @return string[] candidates Completion candidates
local function complete_target(arglead)
	-- We only complete file part when user typed "<rev>:<partial>"
	local rev, file_prefix = arglead:match("^([^:]+):(.*)$")
	if not rev then
		return {}
	end

	-- Fetch revision files through jj
	local cmd = string.format("jj file list -r %s", vim.fn.shellescape(rev))
	local out, ok = runner.execute_command(cmd, nil, nil, true)
	if not ok or not out then
		return {}
	end

	local items = {}
	-- Dedup set for completion candidates.
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
	vim.api.nvim_create_user_command("Jread", function(opts)
		local parsed = parser.parse_file_module_input(opts.args)
		M.read_target({
			rev = parsed and parsed.rev,
			path = parsed and parsed.path,
		})
	end, {
		desc = "Read the target file for the current operation",
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

	create_open_command("Jedit", "tab", "Open the target file in a new tab")
	create_open_command("Jsplit", "horizontal", "Open the target file in a horizontal split")
	create_open_command("Jvsplit", "vertical", "Open the target file in a vertical split")
end

return M
