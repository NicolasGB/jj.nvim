--- @class jj.core.runner
local M = {}

--- Execute a system command and return output with error handling
--- @param cmd string The command to execute
--- @param error_prefix string|nil Optional error message prefix
--- @param input string|nil Optional input to pass to stdin
--- @param silent boolean|nil Optional to silent the notification
--- @return string|nil output The command output, or nil if failed
--- @return boolean success Whether the command succeeded
function M.execute_command(cmd, error_prefix, input, silent)
	local output = vim.fn.system(cmd, input)
	local success = vim.v.shell_error == 0

	if not success then
		local error_message
		if error_prefix then
			error_message = string.format("%s: %s", error_prefix, output)
		else
			error_message = output
		end
		if not silent then
			vim.notify(error_message, vim.log.levels.ERROR, { title = "JJ" })
		end

		return nil, false
	end

	return output, success
end

return M

