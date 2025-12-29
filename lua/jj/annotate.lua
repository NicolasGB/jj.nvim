local M = {}

local utils = require("jj.utils")
local runner = require("jj.core.runner")
local buffer = require("jj.core.buffer")
local parser = require("jj.core.parser")

--- Sets the highlights for the blame bufer
--- @param buf integer
--- @param annotations string[]
local function setup_blame_highlighting(buf, annotations)
	local ns = vim.api.nvim_create_namespace("jj_annotate")
	local seen = {}

	-- Define base highlight groups (link to standard groups)
	vim.api.nvim_set_hl(0, "JJAnnotateDelimiter", { link = "Delimiter" })
	vim.api.nvim_set_hl(0, "JJAnnotateName", { link = "String" })
	vim.api.nvim_set_hl(0, "JJAnnotateDate", { link = "PreProc" })

	for i, line in ipairs(annotations) do
		-- Parse:  "wmkslu | NicolasGB  | 2025-11-23"
		local id_start, id_end, change_id = line:find("^(%S+)")
		local name_start, name_end = line:find("|%s*(. -)%s*|")
		local date_start, date_end = line:find("%d%d%d%d%-%d%d%-%d%d%s%d%d:%d%d:%d%d%s[%+%-]%d%d:%d%d")

		if change_id then
			-- Dynamic color for change_id
			if not seen[change_id] then
				seen[change_id] = true
				local hash = vim.fn.sha256(change_id):sub(1, 6)
				local hl_group = "JJAnnotateId" .. change_id
				vim.api.nvim_set_hl(0, hl_group, { fg = "#" .. hash })
			end

			-- Highlight change ID
			vim.api.nvim_buf_set_extmark(buf, ns, i - 1, id_start - 1, {
				end_col = id_end,
				hl_group = "JJAnnotateId" .. change_id,
			})
		end

		-- Highlight delimiters
		for delim_start in line:gmatch("()| ") do
			vim.api.nvim_buf_set_extmark(buf, ns, i - 1, delim_start - 1, {
				end_col = delim_start,
				hl_group = "JJAnnotateDelimiter",
			})
		end

		-- Highlight name (between first and second |)
		if name_start then
			local actual_name_start = line:find("|") + 2
			local actual_name_end = line:find("|", actual_name_start) - 2
			vim.api.nvim_buf_set_extmark(buf, ns, i - 1, actual_name_start - 1, {
				end_col = actual_name_end + 1,
				hl_group = "JJAnnotateName",
			})
		end

		-- Highlight date
		if date_start then
			vim.api.nvim_buf_set_extmark(buf, ns, i - 1, date_start - 1, {
				end_col = date_end,
				hl_group = "JJAnnotateDate",
			})
		end
	end
end

--- Pads correctly the annotations so that all are the same length
--- @param lines string[] The lines to format
--- @return string[]
local function align_annotations(lines)
	local parsed = {}
	local max_id, max_name, max_date = 0, 0, 0

	for i, line in ipairs(lines) do
		if line ~= "" then
			local parsed_line = parser.parse_annotation_line(line)
			if parsed_line then
				local rev = parsed_line.rev.value
				local name = parsed_line.name.value
				local date = parsed_line.date.value

				parsed[i] = { rev = rev, name = name, date = date }
				max_id = math.max(max_id, #rev)
				max_name = math.max(max_name, #name)
				max_date = math.max(max_date, #date)
			else
				parsed[i] = { raw = line }
			end
		else
			parsed[i] = { raw = "" }
		end
	end

	-- Now that it has been parsed align with max values each line
	local result = {}
	for i, p in ipairs(parsed) do
		if p.rev then
			result[i] = string.format(
				"%-" .. max_id .. "s | %-" .. max_name .. "s | %-" .. max_date .. "s",
				p.rev,
				p.name,
				p.date
			)
		else
			result[i] = p.raw
		end
	end

	return result
end

local function handle_enter()
	-- Parse the current line to extract the revset
	local line = vim.api.nvim_get_current_line()
	local parts = parser.parse_annotation_line(line)
	if not parts or parts.rev.value == "" then
		return
	end

	-- Get the local name
	local filename = vim.b[0].jj_annotation_file

	local cmd = string.format("jj diff --git -r %s %s", parts.rev.value, filename)

	-- Run the command
	local output, success = runner.execute_command(cmd, "Could not run diff from annotation")
	if not success or not output or output == "" then
		return
	end

	-- Create a new buffer with the filetype gitdiff and the output
	local buf, win = buffer.create({
		name = "jj-diff://" .. vim.fn.fnamemodify(filename, ":t") .. "//" .. parts.rev.value,
		split = "tab",
		filetype = "gitdiff",
		bufhidden = "wipe",
	})

	-- Set the lines
	local lines = vim.split(output, "\n", { trimempty = true })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	buffer.set_modified(buf, false)

	-- Autoclose the tab when leaving it to another buffer
	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = buf,
		callback = function()
			-- Only close if actually leaving to a different buffer
			if vim.api.nvim_get_current_buf() ~= buf then
				if vim.api.nvim_win_is_valid(win) then
					vim.cmd("tabclose")
				end
			end
		end,
	})
end

--- Annotates the current file
function M.file()
	if not utils.ensure_jj() then
		return
	end

	local template =
		'join(" | ", commit.change_id().short(6), commit.author().name(), commit.author().timestamp().format("%Y-%m-%d %H:%M:%S %Z")) ++ "\n"'

	local filename = vim.api.nvim_buf_get_name(0)
	if filename == "" then
		utils.notify("Could extract file from buffer", vim.log.levels.ERROR)
		return
	end

	local raw_output, success = runner.execute_command(
		string.format("jj file annotate %s -T '%s'", filename, template),
		"Failed to annotate file"
	)
	if not success or not raw_output then
		return
	end

	local annotations = vim.split(raw_output, "\n", { trimempty = true })

	local size = 0
	for _, line in ipairs(annotations) do
		if line ~= "" then
			size = math.max(size, vim.fn.strdisplaywidth(line))
		end
	end

	-- Capture source window/buffer state BEFORE creating split
	local source_win = vim.api.nvim_get_current_win()
	local source_buf = vim.api.nvim_get_current_buf()
	local source_topline = vim.fn.line("w0")
	local source_had_scrollbind = vim.wo[source_win].scrollbind
	local source_winbar = vim.wo[source_win].winbar

	local buf = buffer.create({
		split = "vertical",
		direction = "left",
		bufhidden = "wipe",
		size = size + 2,
		win_options = {
			wrap = true,
			number = false,
			relativenumber = false,
			cursorline = false,
			signcolumn = "no",
			scrollbind = true,
			winbar = source_winbar,
		},
	})

	-- Set local variables to the buffer
	vim.b[buf].jj_annotation_file = filename

	-- Align annotations and set the text into the buffer
	annotations = align_annotations(annotations)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, annotations)

	setup_blame_highlighting(buf, annotations)
	buffer.set_modifiable(buf, false)

	-- Get annotation window (current after buffer. create)
	local annotation_win = vim.api.nvim_get_current_win()

	-- Set annotation window to match source scroll position
	vim.api.nvim_win_set_cursor(annotation_win, { source_topline, 0 })
	vim.cmd("normal! zt")

	-- Enable scrollbind on source window
	vim.wo[source_win].scrollbind = true

	-- Sync them
	vim.cmd("syncbind")

	-- Create an augroup for this annotation session so we can clean up all autocmds together
	local augroup = vim.api.nvim_create_augroup("JJAnnotate" .. buf, { clear = true })

	-- When source buffer leaves its window (fuzzy finder, : e, etc.)
	vim.api.nvim_create_autocmd("BufLeave", {
		group = augroup,
		buffer = source_buf,
		callback = function()
			if vim.api.nvim_win_is_valid(source_win) then
				vim.wo[source_win].scrollbind = false
			end
		end,
	})

	-- When source buffer comes back to a window
	vim.api.nvim_create_autocmd("BufEnter", {
		group = augroup,
		buffer = source_buf,
		callback = function()
			-- Only re-enable if annotation window still exists
			if vim.api.nvim_win_is_valid(annotation_win) and vim.api.nvim_buf_is_valid(buf) then
				vim.wo[source_win].scrollbind = true
				vim.cmd("syncbind")
			end
		end,
	})

	-- Clean up everything when annotation buffer is destroyed
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = augroup,
		buffer = buf,
		once = true,
		callback = function()
			-- Restore original scrollbind state
			if vim.api.nvim_win_is_valid(source_win) and not source_had_scrollbind then
				vim.wo[source_win].scrollbind = false
			end
			-- Clear the augroup (removes all autocmds in it)
			vim.api.nvim_del_augroup_by_id(augroup)
		end,
	})

	-- Set the keymap enter
	buffer.set_keymaps(buf, {
		{ modes = { "n", "v" }, lhs = "<CR>", rhs = handle_enter, { desc = "Show diff" } },
	})
end

-- Annotates the current line
function M.line() end

return M
