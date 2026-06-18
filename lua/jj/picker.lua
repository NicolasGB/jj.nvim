local utils = require("jj.utils")
local runner = require("jj.core.runner")
local parser = require("jj.core.parser")

--- @class jj.picker

--- @class jj.picker.config
--- @field snacks table|boolean The snacks config

--- @class jj.picker.file
--- @field text string The text to display in the picker
--- @field file string The current path of the file
--- @field status string JJ-style status code (e.g. "M ", "R ") for picker formatting
--- @field rename? string Previous path when this item is a rename
--- @field preview_cmd string[] The command used to preview the item
--- @field confirm_action string The default picker action for the item

--- @class jj.picker.log_line
--- @field text string The text to display in the picker
--- @field symbol string The symbol of the log entry
--- @field rev string The revision of the log entry
--- @field author string The author of the log entry
--- @field time string The time of the log entry
--- @field commit_id string The commit id of the log entry
--- @field description string The description of the log entry
--- @field preview_cmd string[] The command used to preview the item
--- @field confirm_action string The default picker action for the item

--- @class jj.picker.conflict
--- @field text string The text to display in the picker
--- @field symbol string The symbol of the conflict entry
--- @field rev string The revision of the conflict entry
--- @field author string The author of the conflict entry
--- @field description string The description of the conflict entry
--- @field preview_cmd string[] The command used to preview the item
--- @field confirm_action string The default picker action for the item

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
	local diff_ouptut, ok = runner.execute_command("jj --no-pager diff --summary --quiet")
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
		local change = line:match("^(%a)%s")
		local file_info = parser.parse_file_info_from_status_line(line)

		if change and file_info and file_info.new_path then
			local file_path = file_info.new_path
			local item = {
				text = line:sub(3),
				file = file_path,
				status = change .. " ",
				preview_cmd = { "jj", "--no-pager", "diff", file_path },
				confirm_action = "open_and_diff",
			}

			if change == "R" and file_info.old_path and file_info.old_path ~= file_info.new_path then
				item.rename = file_info.old_path
			end

			table.insert(files, item)
		end
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
		"jj --no-pager log %s -r 'all()' -T builtin_log_oneline --config 'template-aliases.\"format_timestamp(timestamp)\"=timestamp'"
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
			-- Split at the first double space which signifies the end of the symbols
			local first_spaces = line:find("%s%s")
			if not first_spaces then
				goto continue
			end
			-- Split the line into parts
			-- The first part is the symbol, the second part is the revision, the third part is the author,
			local symbol = line:sub(1, first_spaces - 1)
			local rest_of_line = line:sub(first_spaces + 1)

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
						preview_cmd = { "jj", "--no-pager", "diff", file_path, "-r", rev, "--stat", "--git" },
						confirm_action = "edit_revision",
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
	if not log_lines or #log_lines == 0 then
		return utils.notify("`Picker`: No file history found", vim.log.levels.INFO)
	end

	if M.config.snacks then
		require("jj.picker.snacks").file_log_history(M.config, log_lines)
	else
		return utils.notify("No `Picker` enabled", vim.log.levels.INFO)
	end
end

--- Gets the list of conflicted revisions
--- @return jj.picker.conflict[]|nil A list of conflicted revisions or nil if not in a jj repo
local function get_conflicts()
	local cmd =
		[[jj log -r 'conflicts()' --no-graph -T 'change_id.shortest() ++ "\t" ++ coalesce(author.name(), "(no author)") ++ "\t" ++ coalesce(description.first_line(), "(no description)") ++ "\n"']]
	local output, ok = runner.execute_command(cmd)
	if not ok then
		return
	end

	if type(output) ~= "string" then
		return utils.notify("Could not get conflicts output", vim.log.levels.ERROR)
	end

	local conflicts = {}
	local lines = vim.split(output, "\n", { trimempty = true })

	for _, line in ipairs(lines) do
		local rev, author, description = line:match("^(.-)\t(.-)\t(.*)$")
		if rev and rev ~= "" then
			local item_author = author or "(no author)"
			local item_description = description or "(no description)"
			table.insert(conflicts, {
				symbol = "!",
				rev = rev,
				author = item_author,
				description = item_description,
				text = string.format("%s %s %s", rev, item_author, item_description),
				preview_cmd = { "jj", "--no-pager", "show", "-r", rev, "--stat", "--git" },
				confirm_action = "resolve_conflict",
			})
		end
	end

	return conflicts
end

--- Displays in the configurated picker the list of conflicted revisions
function M.conflict()
	-- Ensure jj is installed
	if not utils.ensure_jj() then
		return
	end

	local conflicts = get_conflicts()
	if not conflicts or #conflicts == 0 then
		return utils.notify("`Picker`: No conflicts found", vim.log.levels.INFO)
	end

	if M.config.snacks then
		require("jj.picker.snacks").conflict(M.config, conflicts)
	else
		-- Otherwise, use the default vim.ui.select to choose a conflicted revision
		vim.ui.select(conflicts, {
			prompt = "Select conflicted revision",
			format_item = function(item)
				return string.format("%s  %s  %s", item.rev or "", item.author or "", item.description or "")
			end,
		}, function(item)
			if not item or not item.rev then
				return
			end

			--TODO: add a custom tool or default to edit if the user want's to
			local _, ok = runner.execute_command(
				string.format("jj edit %s --ignore-immutable", item.rev),
				string.format("could not edit revision '%s'", item.rev)
			)

			if not ok then
				return
			end

			utils.reload_changed_file_buffers()
			utils.notify(string.format("Editing conflicted revision `%s`", item.rev), vim.log.levels.INFO)

			-- Best-effort: open first conflicted file if one is listed.
			local list_output = runner.execute_command(string.format("jj resolve -r %s --list", item.rev))
			if type(list_output) ~= "string" or list_output == "" then
				return
			end

			for _, line in ipairs(vim.split(list_output, "\n", { trimempty = true })) do
				local path = vim.trim(line:gsub("^[-*]%s+", ""))
				local stat = vim.loop.fs_stat(path)
				if stat and stat.type == "file" then
					vim.cmd("edit " .. vim.fn.fnameescape(path))
					break
				end
			end
		end)
	end
end

return M
