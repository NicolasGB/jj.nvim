--- @class jj.utils
local M = {
	executable_cache = {},
	dependency_cache = {},
}

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
--- @return string|nil output The command output, or nil if failed
--- @return boolean success Whether the command succeeded
function M.execute_command(cmd, error_prefix)
	local output = vim.fn.system(cmd)
	local success = vim.v.shell_error == 0

	if not success then
		local error_message
		if error_prefix then
			error_message = string.format("%s: %s", error_prefix, output)
		else
			error_message = output
		end
		M.notify(error_message, vim.log.levels.ERROR)
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

--- Get a list of files modified in the current jj repository.
--- @return string[] A list of modified file paths
function M.get_modified_files()
	if not M.ensure_jj() then
		return {}
	end

	local handle = io.popen("jj diff --name-only")
	if not handle then
		local error_message = "Error, cannot run jj diff" -- TODO modify error message if necessary
		M.notify(error_message, vim.log.levels.ERROR)
		return {}
	end
	local result = handle:read("*a")
	handle:close()

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
	-- Create a new unlisted, scratch buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, "jujutsu:///DESCRIBE_EDITMSG")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_text)
	vim.api.nvim_set_current_buf(buf)

	-- Configure buffer options
	vim.bo[buf].buftype    = "acwrite" -- Allow custom write handling
	vim.bo[buf].bufhidden  = "wipe" -- Automatically wipe buffer when hidden
	vim.bo[buf].swapfile   = false  -- Disable swapfile
	vim.bo[buf].modifiable = true   -- Allow editing

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
end

return M
