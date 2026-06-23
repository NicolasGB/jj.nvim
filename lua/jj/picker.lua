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
--- @field diff_cmd string The command to get the diff of the file
--- @field confirm_action string The default picker action for the item

--- @class jj.picker.log_line
--- @field text string The text to display in the picker
--- @field rev string The revision of the log entry
--- @field author string The author of the log entry
--- @field time string The time of the log entry
--- @field description string The description of the log entry
--- @field preview_cmd string[] The command used to preview the item
--- @field confirm_action string The default picker action for the item

--- @class jj.picker.conflict_section
--- @field text string The text to display in the picker
--- @field file string Absolute path of the conflicted file
--- @field rel_path string Path of the conflicted file as reported by jj
--- @field pos integer[] {lnum, col} of the conflict opening marker

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

--- Resolve a conflicted revision using configured strategies.
--- @param item jj.picker.conflict|nil
--- @param on_exit? fun(exit_code: number)
local function resolve_conflict(item, on_exit)
	if not item or not item.rev then
		return
	end

	local strategies = require("jj.cmd").config.resolve_strategies or nil
	if strategies and #strategies > 1 then
		vim.ui.select(strategies, {
			prompt = "Select a strategy to resolve the conflict",
			format_item = function(choice)
				return choice.name
			end,
		}, function(choice)
			if not choice then
				return
			end

			require("jj.cmd").resolve({
				rev = item.rev,
				args = choice.args,
				external = choice.external,
				on_exit = on_exit,
			})
		end)
	elseif strategies and #strategies == 1 then
		local choice = strategies[1]
		require("jj.cmd").resolve({
			rev = item.rev,
			args = choice.args,
			external = choice.external,
			on_exit = on_exit,
		})
	else
		require("jj.cmd.resolve").resolve({ rev = item.rev, on_exit = on_exit })
	end
end

M.resolve_conflict = resolve_conflict

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
				diff_cmd = string.format("jj --no-pager diff %s", vim.fn.shellescape(file_path)),
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
		vim.ui.select(files, {
			prompt = "Select changed file",
			format_item = function(item)
				return string.format("%s %s", item.status or "", item.text or item.file or "")
			end,
		}, function(item)
			if item and item.file then
				vim.cmd("edit " .. vim.fn.fnameescape(item.file))
			end
		end)
	end
end

--- Parse file history with a stable no-graph template.
---@param file_path string The path of the file to log
---@return jj.picker.log_line[]|nil A list of log lines or nil if not in a jj repo
local function log_history(file_path)
	local format = table.concat({
		"jj --no-pager log %s",
		"-r 'all() ~ @'",
		"--no-graph",
		[[ -T 'change_id.shortest() ++ "\t" ++ coalesce(author.name(), "(no author)") ++ "\t" ++ committer.timestamp() ++ "\t" ++ coalesce(description.first_line(), "(no description)") ++ "\n"' ]],
	}, " ")
	local output, ok = runner.execute_command(string.format(format, vim.fn.shellescape(file_path)))
	if not ok then
		return
	end

	if type(output) ~= "string" then
		return utils.notify(string.format("Could not get log output for file %s", file_path), vim.log.levels.ERROR)
	end

	local file_history = {}
	local lines = vim.split(output, "\n", { trimempty = true })

	for _, line in ipairs(lines) do
		local parts = vim.split(line, "\t", { plain = true })
		if #parts >= 4 then
			local rev = parts[1]
			local author = parts[2]
			local time_part = parts[3]
			local description = table.concat(vim.list_slice(parts, 4), "\t")
			local short_time = time_part:match("^%d%d%d%d%-%d%d%-%d%d") or time_part

			table.insert(file_history, {
				rev = rev,
				author = author,
				time = time_part,
				description = description,
				text = string.format("%s  %s  %s  %s", rev, author, short_time, description),
				preview_cmd = { "jj", "--no-pager", "diff", file_path, "-r", rev, "--stat", "--git" },
				confirm_action = "edit_revision",
			})
		end
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
		vim.ui.select(log_lines, {
			prompt = "Select revision to edit",
			format_item = function(item)
				return item.text or string.format("%s %s %s", item.rev or "", item.author or "", item.description or "")
			end,
		}, function(item)
			if not item or not item.rev then
				return
			end

			local _, ok = runner.execute_command(
				string.format("jj edit %s --ignore-immutable", item.rev),
				string.format("could not edit revision '%s'", item.rev)
			)

			if ok then
				utils.reload_changed_file_buffers()
				utils.notify(string.format("Editing revision `%s`", item.rev), vim.log.levels.INFO)
			end
		end)
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
			resolve_conflict(item, function(exit_code)
				if exit_code == 0 and item and item.rev then
					utils.notify(string.format("Successfully resolved `%s`", item.rev), vim.log.levels.INFO)
				end
			end)
		end)
	end
end

--- Lists the individual conflict sections present in the current revision (`@`).
---
--- The `conflicted_files()` template reports the conflicted files but not the
--- location of the conflicts inside them, so each file is scanned for opening
--- conflict markers (lines starting with `<<<<<<<`) to build one entry per
--- conflict section. Each file is emitted as a NUL-terminated display path
--- followed by a NUL-terminated absolute path; NUL is used because it is the
--- only byte that cannot occur in a path, so the raw output is read to preserve
--- it.
--- @return jj.picker.conflict_section[]|nil A list of conflict sections or nil if not in a jj repo
local function get_conflict_sections()
	local output, ok, _ = runner.execute_command_raw(
		[[jj log --no-graph --quiet -r @ -T 'self.conflicted_files().map(|e| e.path().display() ++ "\0" ++ e.path().absolute() ++ "\0")']]
	)
	if not ok then
		return
	end

	if type(output) ~= "string" then
		return utils.notify("Could not get conflict list output", vim.log.levels.ERROR)
	end

	local sections = {}

	for _, entry in ipairs(parser.parse_conflicted_files(output)) do
		local file_lines = vim.fn.filereadable(entry.abs_path) == 1 and vim.fn.readfile(entry.abs_path) or {}
		vim.list_extend(sections, parser.scan_conflict_sections(entry.rel_path, entry.abs_path, file_lines))
	end

	return sections
end

--- Displays a picker with each individual conflict section in the current revision (`@`).
function M.conflict_sections()
	-- Ensure jj is installed
	if not utils.ensure_jj() then
		return
	end

	local sections = get_conflict_sections()
	if not sections or #sections == 0 then
		return utils.notify("`Picker`: No conflicts found in the current revision", vim.log.levels.INFO)
	end

	if M.config.snacks then
		require("jj.picker.snacks").conflict_sections(M.config, sections)
	else
		-- Otherwise, use the default vim.ui.select to navigate to a conflict
		vim.ui.select(sections, {
			prompt = "Select conflict to navigate to",
			format_item = function(item)
				return item.text
			end,
		}, function(item)
			if not item then
				return
			end
			vim.cmd("edit " .. vim.fn.fnameescape(item.file))
			pcall(vim.api.nvim_win_set_cursor, 0, item.pos)
		end)
	end
end

return M
