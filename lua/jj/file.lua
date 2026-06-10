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

--- Encoding settings mirroring the corresponding buffer options.
--- @class jj.file.enc
--- @field fenc string 'fileencoding', "" means utf-8/internal
--- @field bomb boolean 'bomb'
--- @field ff "unix"|"dos"|"mac" 'fileformat'

--- @param buf integer
--- @return jj.file.enc
function M.get_buf_encoding(buf)
	return {
		fenc = vim.bo[buf].fileencoding,
		bomb = vim.bo[buf].bomb,
		ff = vim.bo[buf].fileformat,
	}
end

--- Apply encoding settings to a buffer's options
--- @param buf integer
--- @param enc jj.file.enc
function M.set_buf_encoding(buf, enc)
	vim.bo[buf].fileencoding = enc.fenc
	vim.bo[buf].bomb = enc.bomb
	vim.bo[buf].fileformat = enc.ff
end

--- Decode raw file bytes into UTF-8 lines according to `enc`.
--- When `enc` is omitted, it is auto-detected from the raw bytes.
--- @param raw string
--- @param enc? jj.file.enc
--- @return string[]|nil lines nil on conversion failure
--- @return boolean|string had_eol Whether the content had a trailing
---				 newline; an error message when `lines` is nil
--- @return jj.file.enc enc The encoding used (detected or passed in)
local function decode(raw, enc)
	local auto_detected = false
	if not enc then
		auto_detected = true
		enc = { fenc = "", bomb = false, ff = "unix" }
		if raw:sub(1, 2) == "\255\254" then
			enc.fenc = "utf-16le"
			enc.bomb = true
		elseif raw:sub(1, 2) == "\254\255" then
			enc.fenc = "utf-16be"
			enc.bomb = true
		elseif raw:sub(1, 3) == "\239\187\191" then
			enc.bomb = true
		end
	end

	if enc.fenc ~= "" and enc.fenc ~= "utf-8" then
		local converted = vim.iconv(raw, enc.fenc, "utf-8")
		if not converted then
			return nil, string.format("Could not convert content from '%s' to utf-8", enc.fenc), enc
		end
		raw = converted
	end

	if auto_detected then
		if raw:find("\r\n", 1, true) then
			enc.ff = "dos"
		elseif raw:find("\r", 1, true) then
			enc.ff = "mac"
		end
	end

	if enc.bomb then
		raw = raw:gsub("^\239\187\191", "")
	end
	if enc.ff == "dos" then
		raw = raw:gsub("\r\n", "\n")
	elseif enc.ff == "mac" then
		raw = raw:gsub("\r", "\n")
	end
	local had_eol = raw:sub(-1) == "\n"
	local lines = vim.split(raw, "\n", { plain = true, trimempty = false })
	if had_eol then
		table.remove(lines, #lines)
	end
	return lines, had_eol, enc
end

--- Byte order marks by 'fileencoding' value.
local BOMS = {
	["utf-8"] = "\239\187\191",
	["utf-16le"] = "\255\254",
	["utf-16"] = "\254\255",
	["utf-16be"] = "\254\255",
}

--- Serialize UTF-8 lines back into raw file bytes.
--- @param lines string[]
--- @param eol boolean Whether to append a trailing newline
--- @param enc jj.file.enc
--- @return string|nil content nil on conversion failure
--- @return string|nil err Error message when content is nil
local function encode(lines, eol, enc)
	local text = table.concat(lines, "\n")
	if eol then
		text = text .. "\n"
	end
	if enc.ff == "dos" then
		text = text:gsub("\n", "\r\n")
	elseif enc.ff == "mac" then
		text = text:gsub("\n", "\r")
	end
	if enc.fenc ~= "" and enc.fenc ~= "utf-8" then
		local converted = vim.iconv(text, "utf-8", enc.fenc)
		if not converted then
			return nil, string.format("Could not convert content from utf-8 to '%s'", enc.fenc)
		end
    -- Strip the converter bom
		local bom = BOMS[enc.fenc:lower()]
		if bom and vim.startswith(converted, bom) then
			converted = converted:sub(#bom + 1)
		end
		text = converted
	end
	if enc.bomb then
		local bom = BOMS[(enc.fenc ~= "" and enc.fenc or "utf-8"):lower()]
		if bom then
			text = bom .. text
		end
	end
	return text
end

-- Exposed for unit tests (tests/run_tests.lua); not part of the public API.
M._decode = decode
M._encode = encode

--- Fetch file content from jj synchronously.
--- Returns lines with blank lines preserved; trailing empty line removed.
--- @param rev string The revision (change ID or other revset)
--- @param path string Cwd-relative path
--- @param enc? jj.file.enc Encoding to interpret the content with
---				(default: auto-detected from content)
--- @return string[] lines
--- @return boolean had_eol Whether the content had a trailing newline
--- @return boolean ok Whether the command succeeded
--- @return jj.file.enc used_enc The encoding used to decode the content
local function get_file_content(rev, path, enc)
	local raw, ok = runner.execute_command_raw(
		string.format("jj file show -r %s %s", vim.fn.shellescape(rev), vim.fn.shellescape(path)),
		nil,
		true
	)
	if not ok or not raw then
		return {}, false, false, enc or { fenc = "", bomb = false, ff = "unix" }
	end
	local lines, had_eol, used_enc = decode(raw, enc)
	if not lines then
		utils.notify(had_eol --[[@as string]], vim.log.levels.ERROR)
		return {}, false, false, used_enc
	end
	return lines, had_eol --[[@as boolean]], true, used_enc
end
M.get_file_content = get_file_content

--- Reads a target file revision into the current buffer (undoable).
--- @param opts? jj.file.read_target_opts
function M.read_target(opts)
	local revision = opts and opts.rev or "@"
	local raw_path = opts and opts.path or "%"
	local path, normalize_err = utils.normalize_relative_path(raw_path)
	if not path then
		utils.notify(normalize_err or "Could not normalize path", vim.log.levels.ERROR)
		return
	end

	local buf = vim.api.nvim_get_current_buf()
	-- Borrow the buffer's existing encoding if it already has one set;
	-- otherwise auto-detect from the raw bytes.
	local enc = nil
	local buf_fenc = vim.bo[buf].fileencoding
	if buf_fenc ~= "" then
		enc = M.get_buf_encoding(buf)
	end

	local cmd = string.format("jj file show -r %s %s", vim.fn.shellescape(revision), vim.fn.shellescape(path))
	runner.execute_command_raw_async(cmd, function(raw)
		local lines, had_eol, used_enc = decode(raw, enc)
		if not lines then
			utils.notify(had_eol --[[@as string]], vim.log.levels.ERROR)
			return
		end
		if vim.bo[buf].modifiable == false then
			utils.notify("Current buffer is not modifiable", vim.log.levels.ERROR)
			return
		end
		M.set_buf_encoding(buf, used_enc)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].eol = had_eol --[[@as boolean]]
		vim.bo[buf].modified = true
	end, string.format("Could not read `%s` from `%s`", path, revision))
end

--- Write buffer content back into a jj revision, bypassing the working copy.
--- @param buf integer
--- @param change_id string
--- @param rel_path string Repository-relative path of the file
--- @param force boolean Whether to bypass the immutability check (`:w!`)
local function write_revision_file(buf, change_id, rel_path, force)
	if utils.is_change_immutable(change_id) then
		if not force then
			utils.notify("Cannot write to immutable revision: " .. change_id, vim.log.levels.ERROR)
			return
		end
	end

	local new_content, enc_err =
		encode(vim.api.nvim_buf_get_lines(buf, 0, -1, false), vim.bo[buf].eol, M.get_buf_encoding(buf))
	if not new_content then
		utils.notify(enc_err or "Could not encode buffer content", vim.log.levels.ERROR)
		return
	end

	local tmp = vim.fn.tempname()
	local cf = io.open(tmp, "wb")
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
	local path, normalize_err = utils.normalize_relative_path(raw_path)
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
	if not ok or not raw_ids then return end
	local ids = vim.split(vim.trim(raw_ids), "\n", { trimempty = true })
	if #ids ~= 1 then
		utils.notify(string.format("Revision '%s' is ambiguous", revision), vim.log.levels.ERROR)
		return
	end
	local change_id = ids[1]

	local lines, had_eol, ok_read, used_enc = get_file_content(change_id, path)
	if not ok_read then
		utils.notify(string.format("Could not read `%s` from `%s`", path, change_id), vim.log.levels.ERROR)
		return
	end
	local ft = vim.filetype.match({ filename = path })

	local buf, _ = buffer.create({
		name = string.format("jj://%s/%s", change_id, path),
		split = opts.split or "current",
		modifiable = true,
		buftype = "acwrite",
		bufhidden = "wipe",
		filetype = ft,
	})
	M.set_buf_encoding(buf, used_enc)
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
			write_revision_file(buf, change_id, path, vim.v.cmdbang == 1)
		end,
	})

	vim.bo[buf].modified = false
	vim.bo[buf].modifiable = not utils.is_change_immutable(change_id)
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
			if not change_id or not path then return end
			local lines, had_eol, ok_read, used_enc = get_file_content(change_id, path)
			if not ok_read then
				utils.notify(string.format("Could not read `%s` from `%s`", path, change_id), vim.log.levels.ERROR)
				return
			end
			local buf = vim.api.nvim_get_current_buf()
			M.set_buf_encoding(buf, used_enc)
			vim.bo[buf].modifiable = true
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
			vim.bo[buf].eol = had_eol
			vim.bo[buf].modified = false
			vim.bo[buf].modifiable = not utils.is_change_immutable(change_id)
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
