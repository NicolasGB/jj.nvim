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
local default_log_opts = { summary = false, reversed = false, no_graph = false, limit = 20, raw_flats = nil }

--- Jujutsu log
--- @param opts? jj.cmd.log_opts Optional command options
function M.log(opts)
	if not utils.ensure_jj() then
		return
	end

	local jj_cmd = "jj log"
	local merged_opts = vim.tbl_extend("force", default_log_opts, opts or {})

	-- If a raw has been given simply execute it as is
	if merged_opts.raw then
		return terminal.run(string.format("%s %s", jj_cmd, merged_opts.raw), M.log_keymaps())
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
	local _, success = runner.execute_command(cmd, string.format(cfg.err, revset))
	if not success then
		return
	end

	utils.notify(string.format(cfg.ok, revset), vim.log.levels.INFO)
	-- Refresh the log buffer after creating the change.
	require("jj.cmd").log()
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

--- Handle keypress enter on `jj log` buffer to edit a revision.
--- If ignore_immut is true, adds --ignore-immutable to the command.
--- Silently returns if no revision is found or the jj command fails.
--- On success, notifies and refreshes the log buffer.
--- @param ignore_immut? boolean Pass --ignore-immutable to jj edit when true.
function M.handle_log_enter(ignore_immut)
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
	local _, success = runner.execute_command(cmd, "Error editing change")
	if not success then
		return
	end

	utils.notify(string.format("Editing change: `%s`", revset), vim.log.levels.INFO)
	-- Close the terminal buffer
	terminal.close_terminal_buffer()
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
	local cfg = cmd.config.keymaps.log or {}

	local specs = {
		edit = {
			desc = "Checkout revision under cursor",
			handler = M.handle_log_enter,
			args = { false },
		},
		edit_immutable = {
			desc = "Checkout revision under cursor (ignores immutability)",
			handler = M.handle_log_enter,
			args = { true },
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
	}

	return cmd.merge_keymaps(cmd.resolve_keymaps_from_specs(cfg, specs), cmd.terminal_keymaps())
end

return M
