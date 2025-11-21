local utils = require("jj.utils")
local runner = require("jj.core.runner")

--- @class jj.picker

--- @class jj.picker.config
--- @field snacks table|boolean The snacks config

--- @class jj.picker.file
--- @field file string The path of the file
--- @field change string The type of change in the file
--- @field diff_cmd string The command to get the diff of the file

--- @class jj.picker.log_line
--- @field symbol string The symbol of the log entry
--- @field rev string The revision of the log entry
--- @field author string The author of the log entry
--- @field time string The time of the log entry
--- @field commit_id string The commit id of the log entry
--- @field description string The description of the log entry
--- @field diff_cmd string The command to get the diff of the file

local M = {
	--- @type jj.picker.config
	config = {
		snacks = {},
	},
}

--- Initializes the picker
--- @param opts jj.picker.config
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

--- Gets the files in the current jj repository
--- @return jj.picker.file[]|nil A list of files with their changes or nil if not in a jj repo
local function get_files()
	local diff_ouptut, ok = runner.execute_command("jj diff --summary --quiet")
	if not ok then
		return
	end

	if type(diff_ouptut) ~= "string" then
		return utils.notify("Could not get diff output", vim.log.levels.ERROR)
	end

	local files = {}

	-- Split the output into lines
	local lines = vim.split(diff_ouptut, "\n", { trimempty = true })

	for _, line in ipairs(lines) do
		local change, file_path = line:match("^(%a)%s(.+)$")

		table.insert(files, {
			text = file_path,
			file = file_path,
			change = change,
			diff_cmd = string.format("jj diff %s", file_path),
		})
	end

	return files
end

--- Displays in the configurated picker the status of the files
function M.status()
	-- Ensure jj is installed
	if not utils.ensure_jj() then
		return
	end

	local files = get_files()
	if not files or #files == 0 then
		return utils.notify("`Picker`: No diffs found", vim.log.levels.INFO)
	end

	if M.config.snacks then
		require("jj.picker.snacks").status(M.config, files)
	else
		return utils.notify("No `Picker` enabled", vim.log.levels.INFO)
	end
end

---Parse jj log oneline
---@param file_path string The path of the file to log
---@return jj.picker.log_line[]|nil A list of log lines or nil if not in a jj repo
local function log_history(file_path)
	local format =
		"jj log %s -r 'all()' -T builtin_log_oneline --config 'template-aliases.\"format_timestamp(timestamp)\"=timestamp'"
	local output, ok = runner.execute_command(string.format(format, file_path))
	if not ok then
		return
	end

	if type(output) ~= "string" then
		return utils.notify(string.format("Could not get log output for file %s", file_path), vim.log.levels.ERROR)
	end

	local file_history = {}
	local lines = vim.split(output, "\n", { trimempty = true })

	for _, line in ipairs(lines) do
		-- Skip root line and elided revisions
		local not_empty = line:match("%S")
		local root = line:match("root%(%)")
		local elided = line:match("~%s*%(elided revisions%)%s*$")

		if not_empty and not root and not elided then
			-- Pattern: [symbol] [rev] [author] [time] [commit_id] [description]
			-- Example: @  w ngou0210 10 seconds ago e (no description set)
			-- Split at the first space after the symbol
			local first_space = line:find("%s")
			if not first_space then
				goto continue
			end
			-- Split the line into parts
			-- The first part is the symbol, the second part is the revision, the third part is the author,
			local symbol = line:sub(1, first_space - 1)
			local rest_of_line = line:sub(first_space + 1)

			local rev, author, time_part, commit_id, description =
				rest_of_line:match("^%s*(%S+)%s+(%S+)%s+(.-)%s+([%w]+)%s+(.*)$")

			-- It does not make much sense to show the current commit
			if symbol and symbol ~= "@" then
				if rev and author and commit_id then
					table.insert(file_history, {
						symbol = symbol or "",
						rev = rev,
						author = author,
						time = time_part or "",
						commit_id = commit_id,
						description = description or "",
						text = line,
						diff_cmd = string.format("jj diff %s -r %s --stat --git", file_path, rev),
					})
				end
			end
		end
		::continue::
	end

	return file_history
end

function M.file_history()
	-- Ensure jj is installed
	if not utils.ensure_jj() then
		return
	end

	local file = vim.fn.expand("%:p")

	local log_lines = log_history(file)

	if M.config.snacks then
		require("jj.picker.snacks").file_log_history(M.config, log_lines)
	else
		return utils.notify("No `Picker` enabled", vim.log.levels.INFO)
	end
end

return M
