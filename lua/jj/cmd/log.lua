--- @class jj.cmd.log
local M = {}

local utils = require("jj.utils")
local runner = require("jj.core.runner")
local parser = require("jj.core.parser")
local terminal = require("jj.ui.terminal")

--- @class jj.cmd.log_opts
--- @field summary? boolean
--- @field reversed? boolean
--- @field no_graph? boolean
--- @field limit? uinteger
--- @field revisions? string
--- @field raw_flags? string

---@type jj.cmd.log_opts
local default_log_opts = { summary = false, reversed = false, no_graph = false, limit = 20, raw_flags = nil }

--- Jujutsu log
--- @param opts? jj.cmd.log_opts Optional command options
function M.log(opts)
	if not utils.ensure_jj() then
		return
	end

	-- If a log was already being displayed before this command we will want to maintain the cursor position
	if terminal.state.buf_cmd == "log" then
		terminal.store_cursor_position()
	end

	local jj_cmd = "jj log"
	local merged_opts = vim.tbl_extend("force", default_log_opts, opts or {})

	-- If a raw has been given simply execute it as is
	if merged_opts.raw_flags then
		return terminal.run(string.format("%s %s", jj_cmd, merged_opts.raw_flags), M.log_keymaps())
	end

	for key, value in pairs(merged_opts) do
		key = key:gsub("_", "-")
		if key == "limit" and value then
			jj_cmd = string.format("%s --%s %d", jj_cmd, key, value)
		elseif key == "revisions" and value then
			jj_cmd = string.format("%s --%s %s", jj_cmd, key, value)
		elseif value then
			jj_cmd = string.format("%s --%s", jj_cmd, key)
		end
	end

	terminal.run(jj_cmd, M.log_keymaps())
end

---
--- Create a new change relative to the revision under the cursor in a jj log buffer.
--- Behavior:
---   flag == nil       -> branch off the current revision
---   flag == "after"   -> create a new change after the current revision (-A)
--- If ignore_immut is true, adds --ignore-immutable to the command.
--- Silently returns if no revision is found or the jj command fails.
--- On success, notifies and refreshes the log buffer.
--- @param flag? 'after' Position relative to the current revision; nil to branch off.
--- @param ignore_immut? boolean Pass --ignore-immutable to jj when true.
function M.handle_log_new(flag, ignore_immut)
	local line = vim.api.nvim_get_current_line()
	local revset = parser.get_rev_from_log_line(line)
	if not revset or revset == "" then
		return
	end

	-- Mapping for flag-specific options and messages.
	local flag_map = {
		after = {
			opt = "-A",
			err = "Error creating new change after: `%s`",
			ok = "Successfully created change after: `%s`",
		},
		default = {
			opt = "",
			err = "Error creating new change branching off `%s`",
			ok = "Successfully created change branching off `%s`",
		},
	}

	local cfg = flag_map[flag] or flag_map.default

	-- Build command parts
	local cmd_parts = { "jj", "new" }
	if cfg.opt ~= "" then
		table.insert(cmd_parts, cfg.opt)
	end
	table.insert(cmd_parts, revset)
	if ignore_immut then
		table.insert(cmd_parts, "--ignore-immutable")
	end

	local cmd = table.concat(cmd_parts, " ")
	runner.execute_command_async(cmd, function()
		utils.notify(string.format(cfg.ok, revset), vim.log.levels.INFO)
		-- Refresh the log buffer after creating the change.
		require("jj.cmd").log()
	end, string.format(cfg.err, revset))
end

--- Handle diffing a log line
function M.handle_log_diff()
	local line = vim.api.nvim_get_current_line()
	local revset = parser.get_rev_from_log_line(line)

	if revset then
		local cmd = string.format("jj show %s", revset)
		terminal.run_floating(cmd, require("jj.cmd").floating_keymaps())
	else
		utils.notify("No valid revision found in the log line", vim.log.levels.ERROR)
	end
end

--- Handle describing a log line
function M.handle_log_describe()
	local line = vim.api.nvim_get_current_line()
	local revset = parser.get_rev_from_log_line(line)
	if revset then
		require("jj.cmd").describe(nil, revset)
	else
		utils.notify("No valid revision found in the log line", vim.log.levels.ERROR)
	end
end

--- Handle keypress edit on `jj log` buffer to edit a revision.
--- If ignore_immut is true, adds --ignore-immutable to the command.
--- Silently returns if no revision is found or the jj command fails.
--- On success, notifies and refreshes the log buffer.
--- @param ignore_immut? boolean Pass --ignore-immutable to jj edit when true.
--- @param close_on_exit? boolean Close the log buffer after editing when true.
function M.handle_log_edit(ignore_immut, close_on_exit)
	local line = vim.api.nvim_get_current_line()
	local revset = parser.get_rev_from_log_line(line)
	if not revset or revset == "" then
		return
	end

	-- If we found a revision, edit it.

	-- Build command parts.
	local cmd_parts = { "jj", "edit" }
	if ignore_immut then
		table.insert(cmd_parts, "--ignore-immutable")
	end

	table.insert(cmd_parts, revset)

	-- Build cmd string
	local cmd = table.concat(cmd_parts, " ")

	-- Try to execute cmd
	runner.execute_command_async(cmd, function()
		-- Close the terminal buffer
		if close_on_exit then
			utils.notify(string.format("Editing change: `%s`", revset), vim.log.levels.INFO)
			terminal.close_terminal_buffer()
		else
			M.log({})
		end
	end, "Error editing change")
end

--- Handle abandon `jj log` buffer.
--- If ignore_immut is true, adds --ignore-immutable to the command.
--- Silently returns if no revision is found or the jj command fails.
--- On success, notifies and refreshes the log buffer.
--- @param ignore_immut? boolean Pass --ignore-immutable to jj abandon when true.
function M.handle_log_abandon(ignore_immut)
	local line = vim.api.nvim_get_current_line()
	local revset = parser.get_rev_from_log_line(line)
	if not revset or revset == "" then
		return
	end

	-- If we found a revision, abandon it.

	-- Build command parts.
	local cmd_parts = { "jj", "abandon" }
	if ignore_immut then
		table.insert(cmd_parts, "--ignore-immutable")
	end

	table.insert(cmd_parts, revset)

	-- Build cmd string
	local cmd = table.concat(cmd_parts, " ")

	-- Try to execute cmd
	runner.execute_command_async(cmd, function()
		utils.notify(string.format("Abandoned change: `%s`", revset), vim.log.levels.INFO)
		M.log({})
	end, "Error abandoning change")
end

--- Handle fetching from `jj log` buffer.
function M.handle_log_fetch()
	local cmd = "jj git fetch"
	utils.notify("Fetching from remote...", vim.log.levels.INFO)
	runner.execute_command_async(cmd, function()
		utils.notify("Successfully fetched from remote", vim.log.levels.INFO)
		M.log({})
	end, "Error fetching from remote")
end

--- Handle pushing from `jj log` buffer.
function M.handle_log_push_all()
	local cmd = "jj git push"
	utils.notify("Pushing `ALL` bookmarks", vim.log.levels.INFO)
	runner.execute_command_async(cmd, function()
		utils.notify("Successfully pushed all to remote", vim.log.levels.INFO)
		M.log({})
	end, "Error pushing to remote")
end

--- Handle log pushing bookmark from current line in `jj log` buffer.
function M.handle_log_push_bookmark()
	local line = vim.api.nvim_get_current_line()
	local revset = parser.get_rev_from_log_line(line)
	if not revset or revset == "" then
		return
	end
	-- If we found a revfision get it's bookmark and push it
	local bookmark, success = runner.execute_command(
		string.format("jj log -r %s -T 'bookmarks' --no-graph", revset),
		string.format("Error retrieving bookmark for `%s`", revset),
		nil,
		false
	)
	if not success or not bookmark then
		return
	end

	-- If there's a * trim it (bookmarks with modifications have *)
	bookmark = bookmark:gsub("%*", ""):gsub("^%s+", ""):gsub("%s+$", "")

	if bookmark == "" then
		utils.notify("No bookmark found for revision", vim.log.levels.ERROR)
		return
	end

	-- Push the bookmark from the revset found
	local cmd = string.format("jj git push --bookmark %s -N", bookmark)
	utils.notify(string.format("Pushing bookmark `%s`...", bookmark), vim.log.levels.INFO)
	runner.execute_command_async(cmd, function()
		utils.notify(string.format("Successfully pushed bookmark for `%s`", revset), vim.log.levels.INFO)
		M.log({})
	end, string.format("Error pushing bookmark for `%s`", revset))
end

--- Resolve log keymaps from config, filtering out nil values
--- @return jj.core.buffer.keymap[]
function M.log_keymaps()
	local cmd = require("jj.cmd")

	-- Reduce repetition by declaring a specification table.
	-- Each entry maps the config key name to:
	--   desc: Keybind description
	--   handler: function to call
	--   args: optional list of arguments passed to handler
	local keymaps = cmd.config.keymaps.log or {}
	local close_on_edit = cmd.config.log.close_on_edit or false

	local specs = {
		edit = {
			desc = "Checkout revision under cursor",
			handler = M.handle_log_edit,
			args = { false, close_on_edit },
		},
		edit_immutable = {
			desc = "Checkout revision under cursor (ignores immutability)",
			handler = M.handle_log_edit,
			args = { true, close_on_edit },
		},
		describe = {
			desc = "Describe revision under cursor",
			handler = M.handle_log_describe,
		},
		diff = {
			desc = "Diff revision under cursor",
			handler = M.handle_log_diff,
		},
		new = {
			desc = "Create new change branching off revision under cursor",
			handler = M.handle_log_new,
			args = { nil, false },
		},
		new_after = {
			desc = "Create new change after revision under cursor",
			handler = M.handle_log_new,
			args = { "after", false },
		},
		new_after_immutable = {
			desc = "Create new change after revision under cursor (ignore immutable)",
			handler = M.handle_log_new,
			args = { "after", true },
		},
		undo = {
			desc = "Undo last change",
			handler = cmd.undo,
		},
		redo = {
			desc = "Redo last undone change",
			handler = cmd.redo,
		},
		abandon = {
			desc = "Abandon revision under cursor",
			handler = M.handle_log_abandon,
			-- As of now i'm only exposing the non ignore-immutable version of abandon in the keymaps
			-- Maybe in the future we can add another keymap for that, if people request it
			args = { false },
		},
		fetch = {
			desc = "Fetch from remote",
			handler = M.handle_log_fetch,
		},
		push_all = {
			desc = "Push all to remote",
			handler = M.handle_log_push_all,
		},
		push = {
			desc = "Push bookmark of revision under cursor to remote",
			handler = M.handle_log_push_bookmark,
		},
	}

	return cmd.merge_keymaps(cmd.resolve_keymaps_from_specs(keymaps, specs), cmd.terminal_keymaps())
end

return M
