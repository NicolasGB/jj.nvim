--- @class jj.utils
--- @field highlights jj.utils.highlights Highlight configuration

---@class jj.utils.highlights
---@field added table Highlight settings for added lines
---@field modified table Highlight settings for modified lines
---@field deleted table Highlight settings for deleted lines
---@field renamed table Highlight settings for renamed lines

local M = {
	executable_cache = {},
	dependency_cache = {},
	highlights_initialized = false,
	highlights = {
		added = { fg = "#3fb950", ctermfg = "Green" },
		modified = { fg = "#56d4dd", ctermfg = "Cyan" },
		deleted = { fg = "#f85149", ctermfg = "Red" },
		renamed = { fg = "#d29922", ctermfg = "Yellow" },
	},
}

-- Initialize highlight groups once
local function init_highlights()
	if M.highlights_initialized then
		return
	end

	vim.api.nvim_set_hl(0, "JJComment", { link = "Comment" })
	vim.api.nvim_set_hl(0, "JJAdded", M.highlights.added)
	vim.api.nvim_set_hl(0, "JJModified", M.highlights.modified)
	vim.api.nvim_set_hl(0, "JJDeleted", M.highlights.deleted)
	vim.api.nvim_set_hl(0, "JJRenamed", M.highlights.renamed)

	M.highlights_initialized = true
end

--- Setup function to configure highlights and other options
---@param opts? jj.utils Configuration options
function M.setup(opts)
	opts = opts or {}

	-- Merge user highlights with defaults
	if opts.highlights then
		M.highlights = vim.tbl_deep_extend("force", M.highlights, opts.highlights)
	end

	-- Reset highlights flag to force re-initialization with new highlights
	if M.highlights_initialized then
		M.highlights_initialized = false
		init_highlights()
	end
end

--- Cache for executable checks to avoid repeated system calls

--- Check if an executable exists in PATH
--- @param name string The name of the executable to check
--- @return boolean True if executable exists, false otherwise
function M.has_executable(name)
	if M.executable_cache[name] ~= nil then
		return M.executable_cache[name]
	end

	local exists = vim.fn.executable(name) == 1
	M.executable_cache[name] = exists
	return exists
end

--- Check if the dependency is currently installed
--- @param module string The dependency module
--- @return boolean
function M.has_dependency(module)
	if M.dependency_cache[module] ~= nil then
		return true
	end

	local exists, _ = pcall(require, module)
	if not exists then
		M.notify(string.format("Module %s not installed", module), vim.log.levels.ERROR)
		return false
	end

	return true
end

--- Clear the executable cache (useful for testing or if PATH changes)
function M.clear_executable_cache()
	M.executable_cache = {}
end

--- Check if jj executable exists, show error if not
--- @return boolean True if jj exists, false otherwise
function M.ensure_jj()
	if not M.has_executable("jj") then
		M.notify("jj command not found", vim.log.levels.ERROR)
		return false
	end
	return true
end

--- Execute a system command and return output with error handling
--- @param cmd string The command to execute
--- @param error_prefix string|nil Optional error message prefix
--- @param input string|nil Optional input to pass to stdin
--- @param silent boolean|nil Optional to silent the notification
--- @return string|nil output The command output, or nil if failed
--- @return boolean success Whether the command succeeded
function M.execute_command(cmd, error_prefix, input, silent)
	local output
	if input then
		output = vim.fn.system(cmd, input)
	else
		output = vim.fn.system(cmd)
	end
	local success = vim.v.shell_error == 0

	if not success then
		local error_message
		if error_prefix then
			error_message = string.format("%s: %s", error_prefix, output)
		else
			error_message = output
		end
		if not silent then
			M.notify(error_message, vim.log.levels.ERROR)
		end

		return nil, false
	end

	return output, success
end

--- Check if we're in a jj repository
--- @return boolean True if in jj repo, false otherwise
function M.is_jj_repo()
	if not M.ensure_jj() then
		return false
	end

	local _, success = M.execute_command("jj status")
	return success
end

--- Get jj repository root path
--- @return string|nil The repository root path, or nil if not in a repo
function M.get_jj_root()
	if not M.ensure_jj() then
		return nil
	end

	local output, success = M.execute_command("jj root")
	if success and output then
		return vim.trim(output)
	end
	return nil
end

--- Get a list of files with their status in the current jj repository.
--- @return table[] A list of tables with {status = string, file = string}
function M.get_status_files()
	if not M.ensure_jj() then
		return {}
	end

	local result, success = M.execute_command("jj status", "Error getting status")
	if not success or not result then
		return {}
	end

	local files = {}
	-- Parse jj status output: "M filename", "A filename", "D filename", "R old => new"
	for line in result:gmatch("[^\r\n]+") do
		local status, file = line:match("^([MADRC])%s+(.+)$")
		if status and file then
			table.insert(files, { status = status, file = file })
		end
	end

	return files
end

--- Get a list of files modified in the current jj repository.
--- @return string[] A list of modified file paths
function M.get_modified_files()
	if not M.ensure_jj() then
		return {}
	end

	local result, success = M.execute_command("jj diff --name-only", "Error getting diff")
	if not success or not result then
		return {}
	end

	local files = {}
	-- Split the result into lines and add each file to the table
	for file in result:gmatch("[^\r\n]+") do
		table.insert(files, file)
	end

	return files
end

---- Notify function to display messages with a title
--- @param message string The message to display
--- @param level? number The log level (default: INFO)
function M.notify(message, level)
	level = level or vim.log.levels.INFO
	vim.notify(message, level, { title = "JJ", timeout = 3000 })
end

---@param initial_text string[] Lines to initialize the buffer with
---@param on_done fun(buf: string[])? Optional callback called with user text on buffer write
function M.open_ephemeral_buffer(initial_text, on_done)
	-- Initialize highlight groups once
	init_highlights()

	-- Create a horizontal split at the bottom, half the screen height
	local height = math.floor(vim.o.lines / 2)
	vim.cmd(string.format("botright %dsplit", height))

	-- Create a new unlisted, scratch buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, "jujutsu:///DESCRIBE_EDITMSG")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_text)
	vim.api.nvim_win_set_buf(0, buf)

	-- Configure buffer options
	vim.bo[buf].buftype = "acwrite" -- Allow custom write handling
	vim.bo[buf].bufhidden = "wipe" -- Automatically wipe buffer when hidden
	vim.bo[buf].swapfile = false -- Disable swapfile
	vim.bo[buf].modifiable = true -- Allow editing

	-- Create a namespace for our highlights
	local ns_id = vim.api.nvim_create_namespace("jj_describe_highlights")

	-- Function to apply highlights to the buffer
	local function apply_highlights()
		-- Clear existing highlights
		vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

		-- Get all lines
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

		for i, line in ipairs(lines) do
			local line_idx = i - 1 -- 0-indexed

			-- First, check if line starts with JJ: and highlight it as comment
			if line:match("^JJ:") then
				-- Highlight the "JJ:" prefix as comment (first 3 characters)
				vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, 0, {
					end_col = 3,
					hl_group = "JJComment",
				})

				-- Then check for status indicators and highlight the rest of the line
				local status_pos = line:find("[MADRC] ", 4) -- Find status after "JJ:"
				if status_pos then
					local status = line:sub(status_pos, status_pos) -- Get the status character
					local hl_group = nil

					if status == "A" or status == "C" then
						hl_group = "JJAdded"
					elseif status == "M" then
						hl_group = "JJModified"
					elseif status == "D" then
						hl_group = "JJDeleted"
					elseif status == "R" then
						hl_group = "JJRenamed"
					end

					if hl_group then
						-- Highlight from the status character to the end of the line
						vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, status_pos - 1, {
							end_col = #line,
							hl_group = hl_group,
						})
					else
						-- No status, keep rest as comment
						vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, 3, {
							end_col = #line,
							hl_group = "JJComment",
						})
					end
				else
					-- No status indicator, highlight rest of line as comment
					vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, 3, {
						end_col = #line,
						hl_group = "JJComment",
					})
				end
			end
		end
	end

	-- Apply highlights initially
	apply_highlights()

	-- Reapply highlights when text changes
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = buf,
		callback = apply_highlights,
	})

	-- Position cursor at the end (after the last JJ: line) and enter insert mode
	vim.schedule(function()
		-- Get the number of lines in the buffer
		local line_count = vim.api.nvim_buf_line_count(buf)
		-- Move cursor to the last line, column 0
		vim.api.nvim_win_set_cursor(0, { line_count, 0 })
		-- Enter insert mode
		vim.cmd("startinsert")
	end)

	-- Handle :w and :wq commands
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = buf,
		callback = function()
			local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			if on_done then
				on_done(buf_lines)
			end
			vim.bo[buf].modified = false
		end,
	})

	-- Add keymap to close the buffer with 'q' in normal mode
	vim.keymap.set(
		"n",
		"q",
		"<cmd>close!<CR>",
		{ buffer = buf, noremap = true, silent = true, desc = "Close describe buffer" }
	)

	-- Add keymap to close the buffer with '<Esc>' in normal mode
	vim.keymap.set(
		"n",
		"<Esc>",
		"<cmd>close!<CR>",
		{ buffer = buf, noremap = true, silent = true, desc = "Close describe buffer" }
	)
end

--- Parse the current line in the jj status buffer to extract file information.
--- Handles renamed files and regular status lines.
--- @return table|nil A table with {old_path = string, new_path = string, is_rename = boolean}, or nil if parsing fails
function M.parse_file_info_from_status_line()
	local line = vim.api.nvim_get_current_line()

	-- Handle renamed files: "R path/{old_name => new_name}" or "R old_path => new_path"
	local rename_pattern_curly = "^R (.*)/{(.*) => ([^}]+)}"
	local dir_path, old_name, new_name = line:match(rename_pattern_curly)

	if dir_path and old_name and new_name then
		return {
			old_path = dir_path .. "/" .. old_name,
			new_path = dir_path .. "/" .. new_name,
			is_rename = true,
		}
	else
		-- Try simple rename pattern: "R old_path => new_path"
		local rename_pattern_simple = "^R (.*) => (.+)$"
		local old_path, new_path = line:match(rename_pattern_simple)
		if old_path and new_path then
			return {
				old_path = old_path,
				new_path = new_path,
				is_rename = true,
			}
		end
	end

	-- Not a rename, try regular status patterns
	local filepath
	-- Handle renamed files: "R path/{old_name => new_name}" or "R old_path => new_path"
	local rename_pattern_curly_new = "^R (.*)/{.* => ([^}]+)}"
	local dir_path_new, renamed_file = line:match(rename_pattern_curly_new)

	if dir_path_new and renamed_file then
		filepath = dir_path_new .. "/" .. renamed_file
	else
		-- Try simple rename pattern: "R old_path => new_path"
		local rename_pattern_simple_new = "^R .* => (.+)$"
		filepath = line:match(rename_pattern_simple_new)
	end

	if not filepath then
		-- jj status format: "M filename" or "A filename"
		-- Match lines that start with status letter followed by space and filename
		local pattern = "^[MAD?!] (.+)$"
		filepath = line:match(pattern)
	end

	if filepath then
		return {
			old_path = filepath,
			new_path = filepath,
			is_rename = false,
		}
	end

	return nil
end

return M
