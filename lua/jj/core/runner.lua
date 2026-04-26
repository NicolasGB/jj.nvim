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
	local stderr_file = vim.fn.tempname()
	local output = vim.fn.system({ "sh", "-c", string.format("(%s) 2>%s", cmd, vim.fn.shellescape(stderr_file)) }, input)
	local success = vim.v.shell_error == 0

	if not success then
		local stderr_lines = vim.fn.readfile(stderr_file)
		vim.fn.delete(stderr_file)
		local error_output = table.concat(stderr_lines, "\n")
		local msg = error_output ~= "" and error_output or output
		local error_message = error_prefix and string.format("%s: %s", error_prefix, msg) or msg
		if not silent then
			vim.notify(error_message, vim.log.levels.ERROR, { title = "JJ" })
		end
		return nil, false
	end

	vim.fn.delete(stderr_file)
	return output, success
end

--- Execute a system command synchronously and call success callback.
--- @param cmd string The command to execute
--- @param on_success function|nil Callback on success, receives output as parameter
--- @param error_prefix string|nil Optional error message prefix
--- @param input string|nil Optional input to pass to stdin
--- @param silent boolean|nil Optional to silent the notification
--- @return string|nil output The command output, or nil if failed
--- @return boolean success Whether the command succeeded
function M.execute_command_sync(cmd, on_success, error_prefix, input, silent)
	local output, success = M.execute_command(cmd, error_prefix, input, silent)
	if success and on_success then
		on_success(output)
	end
	return output, success
end

--- Execute a system command asynchronously
--- @param cmd string The command to execute
--- @param on_success function|nil Callback on success, receives output as parameter
--- @param error_prefix string|nil Optional error message prefix
--- @param input string|nil Optional input to pass to stdin
--- @param silent boolean|nil Optional to silent the notification
--- @param on_error function|nil Callback on error, receives ouptut as the parameter
function M.execute_command_async(cmd, on_success, error_prefix, input, silent, on_error)
	local stdout_lines = {}
	local stderr_lines = {}

	local job_id = vim.fn.jobstart({ "sh", "-c", cmd }, {
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data)
			vim.list_extend(stdout_lines, data)
		end,
		on_stderr = function(_, data)
			vim.list_extend(stderr_lines, data)
		end,
		on_exit = function(_, exit_code)
			local output = table.concat(stdout_lines, "\n")
			if exit_code == 0 then
				if on_success then
					on_success(output)
				end
			else
				local error_output = table.concat(stderr_lines, "\n")
				local msg = error_output ~= "" and error_output or output
				local error_message = error_prefix and string.format("%s: %s", error_prefix, msg) or msg
				if not silent then
					vim.notify(error_message, vim.log.levels.ERROR, { title = "JJ" })
				end
				if on_error then
					on_error(msg)
				end
			end
		end,
	})

	-- Send stdin if provided
	if input then
		vim.fn.chansend(job_id, input)
		vim.fn.chanclose(job_id, "stdin")
	end
end

return M
