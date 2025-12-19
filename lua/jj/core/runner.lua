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
	local output = vim.fn.system({ "sh", "-c", cmd }, input)
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

--- Execute a system command asynchronously
--- @param cmd string The command to execute
--- @param on_success function|nil Callback on success, receives output as parameter
--- @param error_prefix string|nil Optional error message prefix
--- @param input string|nil Optional input to pass to stdin
--- @param silent boolean|nil Optional to silent the notification
function M.execute_command_async(cmd, on_success, error_prefix, input, silent)
	local output_lines = {}

	local job_id = vim.fn.jobstart({ "sh", "-c", cmd }, {
		on_stdout = function(_, data)
			for _, line in ipairs(data) do
				if line ~= "" then
					table.insert(output_lines, line)
				end
			end
		end,
		on_stderr = function(_, data)
			for _, line in ipairs(data) do
				if line ~= "" then
					table.insert(output_lines, line)
				end
			end
		end,
		on_exit = function(_, exit_code)
			local output = table.concat(output_lines, "\n")
			if exit_code == 0 then
				if on_success then
					on_success(output)
				end
			else
				local error_message
				if error_prefix then
					error_message = string.format("%s: %s", error_prefix, output)
				else
					error_message = output
				end
				if not silent then
					vim.notify(error_message, vim.log.levels.ERROR, { title = "JJ" })
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