--- @class jj.core.runner
local M = {}

local function error_notify(msg, error_prefix, silent)
	local error_message = error_prefix and string.format("%s: %s", error_prefix, msg) or msg
	if not silent then
		vim.notify(error_message, vim.log.levels.ERROR, { title = "JJ" })
	end
end

--- Execute a system command with arguments and return output with error handling
---@param argv string[] The command and its arguments to execute
---@param error_prefix string|nil
---@param input string|nil
---@param silent boolean|nil
--- @return string|nil output The command output, or nil if failed
--- @return boolean success Whether the command succeeded
function M.execute(argv, error_prefix, input, silent)
	local result = vim.system(argv, { stdin = input, text = true }):wait()

	if result.code ~= 0 then
		local msg = result.stderr ~= "" and result.stderr or result.stdout or ""
		error_notify(msg, error_prefix, silent)
		return nil, false
	end
	return result.stdout or "", true
end

--- Execute an argv command with arguments asynchronously and call success callback.
--- @param argv string[] The command and its arguments to execute
--- @param on_success function|nil Callback on success, receives output as parameter
--- @param error_prefix string|nil Optional error message prefix
--- @param input string|nil Optional input to pass to stdin
--- @param silent boolean|nil Optional to silent the notification
--- @param on_error function|nil Callback on error, receives the error message
function M.execute_async(argv, on_success, error_prefix, input, silent, on_error)
	vim.system(
		argv,
		{ stdin = input, text = true },
		vim.schedule_wrap(function(res)
			if res.code == 0 then
				if on_success then
					on_success(res.stdout or "")
				end
			else
				local msg = res.stderr ~= "" and res.stderr or res.stdout or ""
				error_notify(msg, error_prefix, silent)
				if on_error then
					on_error(msg)
				end
			end
		end)
	)
end

--- Execute an argv command with arguments and return raw stdout bytes.
--- Skips replacement of NUL bytes with SOH (0x01).
--- @param argv string[] The command and its arguments to execute
--- @param error_prefix string|nil Optional error message prefix
--- @param silent boolean|nil Optional to silent the notification
--- @return string|nil output Raw stdout bytes, or nil if failed
--- @return boolean success Whether the command succeeded
--- @return string stderr The command's stderr (empty on success)
function M.execute_raw(argv, error_prefix, silent)
	local result = vim.system(argv, { text = false }):wait()
	if result.code ~= 0 then
		local msg = result.stderr ~= "" and result.stderr or result.stdout or ""
		error_notify(msg, error_prefix, silent)
		return nil, false, msg
	end
	return result.stdout or "", true, result.stderr or ""
end

--- Execute an argv command with arguments asynchronously and receive raw stdout bytes.
--- Skips replacement of NUL bytes with SOH (0x01).
--- @param argv string[] The command and its arguments to execute
--- @param on_success function|nil Callback on success, receives raw stdout bytes
--- @param error_prefix string|nil Optional error message prefix
--- @param silent boolean|nil Optional to silent the notification
--- @param on_error function|nil Callback on error, receives the error message
function M.execute_raw_async(argv, on_success, error_prefix, silent, on_error)
	vim.system(
		argv,
		{ text = false },
		vim.schedule_wrap(function(res)
			if res.code == 0 then
				if on_success then
					on_success(res.stdout or "")
				end
			else
				local msg = res.stderr ~= "" and res.stderr or res.stdout or ""
				error_notify(msg, error_prefix, silent)
				if on_error then
					on_error(msg)
				end
			end
		end)
	)
end

return M
