--- @class jj.cmd
local M = {}

local utils = require("jj.utils")
local runner = require("jj.core.runner")
local parser = require("jj.core.parser")
local terminal = require("jj.ui.terminal")
local editor = require("jj.ui.editor")
local diff = require("jj.diff")
local log_module = require("jj.cmd.log")
local describe_module = require("jj.cmd.describe")
local status_module = require("jj.cmd.status")

-- Config for cmd module
--- @class jj.cmd.describe.editor.keymaps
--- @field close? string|string[] Keymaps to close the editor buffer without saving

--- @class jj.cmd.describe.editor
--- @field type? "buffer"|"input" Editor mode for describe command: "buffer" (Git-style editor) or "input" (simple input prompt)
--- @field keymaps? jj.cmd.describe.editor.keymaps Keymaps for the describe editor only when on "buffer" mode.

--- @class jj.cmd.describe
--- @field editor? jj.cmd.describe.editor Options for the describe message editor

--- @class jj.cmd.log.keymaps
--- @field checkout? string|string[] Keymaps for the log command buffer, setting a keymap to nil will disable it
--- @field checkout_immutable? string|string[]
--- @field describe? string|string[]
--- @field diff? string|string[]
--- @field edit? string|string[]
--- @field new? string|string[]
--- @field new_after? string|string[]
--- @field new_after_immutable? string|string[]
--- @field undo? string|string[]
--- @field redo? string|string[]

--- @class jj.cmd.status.keymaps
--- @field open_file? string|string[] Keymaps for the status command buffer, setting a keymap to nil will disable it
--- @field restore_file? string|string[]

--- @class jj.cmd.keymaps
--- @field log? jj.cmd.log.keymaps Keymaps for the log command buffer
--- @field status? jj.cmd.status.keymaps Keymaps for the status command buffer
--- @field close? string|string[] Keymaps for the close keybind

--- @class jj.cmd.opts
--- @field describe? jj.cmd.describe
--- @field keymaps? jj.cmd.keymaps Keymaps for the buffers containing the output of the commands
---
--- @class jj.cmd.keymap_spec
--- @field desc string
--- @field handler function|string
--- @field args? table

--- @alias jj.cmd.keymap_specs table<string, jj.cmd.keymap_spec>

--- @type jj.cmd.opts
M.config = {
	describe = {
		editor = {
			type = "buffer",
			keymaps = {
				close = { "<Esc>", "<C-c>", "q" },
			},
		},
	},
	keymaps = {
		log = {
			edit = "<CR>",
			edit_immutable = "<S-CR>",
			describe = "d",
			diff = "<S-d>",
			new = "n",
			new_after = "<C-n>",
			new_after_immutable = "<S-n>",
			undo = "<S-u>",
			redo = "<S-r>",
		},
		status = {
			open_file = "<CR>",
			restore_file = "<S-x>",
		},
		close = { "q", "<Esc>" },
	},
}

--- Setup the cmd module
--- @param opts jj.cmd.opts: Options to configure the cmd module
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

-- Reexport log function
M.log = log_module.log
-- Reexport describe function
M.describe = describe_module.describe
-- Reexport status function
M.status = status_module.status

--- Merge multiple keymap arrays into one
--- @param ... jj.core.buffer.keymap[][] Keymap arrays to merge
--- @return jj.core.buffer.keymap[]
function M.merge_keymaps(...)
	local merged = {}
	for i = 1, select("#", ...) do
		local km_array = select(i, ...)
		if km_array then
			for _, km in ipairs(km_array) do
				table.insert(merged, km)
			end
		end
	end
	return merged
end

--- Resolve_keymaps_from_specifications
--- @param cfg table<string, string|string[]> The keymap configuration
--- @param specs jj.cmd.keymap_specs The keymap specifications
--- @return jj.core.buffer.keymap[]
function M.resolve_keymaps_from_specs(cfg, specs)
	local keymaps = {}

	for key, spec in pairs(specs) do
		local lhs = cfg[key]
		if lhs and spec.handler then
			if type(lhs) == "table" then
				for _, key_lhs in ipairs(lhs) do
					table.insert(
						keymaps,
						{ modes = "n", lhs = key_lhs, rhs = spec.handler, opts = { desc = spec.desc } }
					)
				end
			else
				table.insert(keymaps, { modes = "n", lhs = lhs, rhs = spec.handler, opts = { desc = spec.desc } })
			end
		end
	end

	return keymaps
end

-- Resolve close keymaps from config
--- @return jj.core.buffer.keymap[]
function M.close_keymaps()
	local cfg = M.config.keymaps.close or {}

	return M.resolve_keymaps_from_specs({ close = cfg }, {
		close = {
			desc = "Close buffer",
			handler = terminal.close_terminal_buffer,
		},
	})
end

--- @class jj.cmd.new_opts
--- @field show_log? boolean Whether or not to display the log command after creating a new
--- @field with_input? boolean Whether or not to use nvim input to decide the parent of the new commit
--- @field args? string The arguments to append to the new command

-- Jujutsu new
--- @param opts? jj.cmd.new_opts
function M.new(opts)
	if not utils.ensure_jj() then
		return
	end

	opts = opts or {}

	--- @param cmd string
	local function execute_new(cmd)
		runner.execute_command(cmd, "Failed to create new change")
		utils.notify("Command `new` was succesful.", vim.log.levels.INFO)
		-- Show the updated log if the user requested it
		if opts.show_log then
			M.log()
		end
	end

	-- If the user wants use input mode
	if opts.with_input then
		if opts.show_log then
			M.log()
		end

		vim.ui.input({
			prompt = "Parent(s) of the new change [default: @]",
		}, function(input)
			if input then
				execute_new(string.format("jj new %s", input))
			end
			terminal.close_terminal_buffer()
		end)
	else
		-- Otherwise follow a classic flow for inputing
		local cmd = "jj new"
		if opts.args then
			cmd = string.format("jj new %s", opts.args)
		end

		execute_new(cmd)
		-- If the show log is enabled show log
		if opts.show_log then
			M.log()
		end
	end
end

-- Jujutsu edit
function M.edit()
	if not utils.ensure_jj() then
		return
	end
	M.log({})
	vim.ui.input({
		prompt = "Change to edit: ",
		default = "",
	}, function(input)
		if input then
			local _, success = runner.execute_command(string.format("jj edit %s", input), "Error editing change")
			if not success then
				return
			end
			M.log({})
		else
			terminal.close_terminal_buffer()
		end
	end)
end

-- Jujutsu squash
function M.squash()
	if not utils.ensure_jj() then
		return
	end

	local cmd = "jj squash"
	local _, success = runner.execute_command(cmd, "Failed to squash")
	if success then
		utils.notify("Command `squash` was succesful.", vim.log.levels.INFO)
		if terminal.state.buf_cmd == "log" then
			M.log()
		end
	end
end

--- @class jj.cmd.diff_opts
--- @field current boolean Wether or not to only diff the current buffer

-- Jujutsu diff
--- @param opts? jj.cmd.diff_opts The options for the diff command
function M.diff(opts)
	if not utils.ensure_jj() then
		return
	end

	local cmd = "jj diff"

	if opts and opts.current then
		local file = vim.fn.expand("%:p")
		if file and file ~= "" then
			cmd = string.format("%s %s", cmd, vim.fn.fnameescape(file))
		else
			utils.notify("Current buffer is not a file", vim.log.levels.ERROR)
			return
		end
	end

	terminal.run(cmd)
end

-- Jujutsu rebase
function M.rebase()
	if not utils.ensure_jj() then
		return
	end

	M.log({})
	vim.ui.input({
		prompt = "Rebase destination: ",
		default = "trunk()",
	}, function(input)
		if input then
			local cmd = string.format("jj rebase -d '%s'", input)
			utils.notify(string.format("Beginning rebase on %s", input), vim.log.levels.INFO)
			local _, success = runner.execute_command(cmd, "Error rebasing")
			if success then
				utils.notify("Rebase successful.", vim.log.levels.INFO)
				M.log({})
			end
		else
			terminal.close_terminal_buffer()
		end
	end)
end

-- Jujutsu create bookmark
function M.bookmark_create()
	if not utils.ensure_jj() then
		return
	end

	M.log({})
	vim.ui.input({
		prompt = "Bookmark name: ",
	}, function(input)
		if input then
			local cmd = string.format("jj b c %s", input)
			local _, success = runner.execute_command(cmd, "Error creating bookmark")
			if success then
				utils.notify(string.format("Bookmark `%s` created successfully for @", input), vim.log.levels.INFO)
				M.log({})
			end
		else
			terminal.close_terminal_buffer()
		end
	end)
end

-- Jujutsu delete bookmark
function M.bookmark_delete()
	if not utils.ensure_jj() then
		return
	end

	M.log({})
	vim.ui.input({
		prompt = "Bookmark name: ",
	}, function(input)
		if input then
			local cmd = string.format("jj b d %s", input)
			local _, success = runner.execute_command(cmd, "Error deleting bookmark")
			if success then
				utils.notify(string.format("Bookmark `%s` deleted successfully.", input), vim.log.levels.INFO)
				M.log({})
			end
		else
			terminal.close_terminal_buffer()
		end
	end)
end

-- Jujutsu undo
function M.undo()
	if not utils.ensure_jj() then
		return
	end

	local cmd = "jj undo"
	local _, success = runner.execute_command(cmd, "Failed to undo")
	if success then
		utils.notify("Command `undo` was succesful.", vim.log.levels.INFO)
		if terminal.state.buf_cmd == "log" then
			M.log({})
		end
	end
end

-- Jujutsu redo
function M.redo()
	if not utils.ensure_jj() then
		return
	end

	local cmd = "jj redo"
	local _, success = runner.execute_command(cmd, "Failed to redo")
	if success then
		utils.notify("Command `redo` was succesful.", vim.log.levels.INFO)
		if terminal.state.buf_cmd == "log" then
			M.log({})
		end
	end
end

--- @param args string|string[] jj command arguments
function M.j(args)
	if not utils.ensure_jj() then
		return
	end

	if #args == 0 then
		local default_cmd_str, success = runner.execute_command(
			"jj config get ui.default-command",
			"Error getting user's default command",
			nil,
			true
		)
		if not success then
			terminal.run("jj")
			return
		end

		local default_cmd = parser.parse_default_cmd(default_cmd_str and default_cmd_str or "")
		if default_cmd == nil then
			terminal.run("jj")
			return
		end
		args = default_cmd
	end

	if type(args) == "string" then
		args = vim.split(args, "%s+")
	end

	local subcommand = args[1]
	local remaining_args = vim.list_slice(args, 2)
	local cmd = string.format("jj %s", table.concat(args, " "))
	local remaining_args_str = table.concat(remaining_args, " ")

	local handlers = {
		describe = function()
			M.describe(remaining_args_str ~= "" and remaining_args_str or nil)
		end,
		desc = function()
			M.describe(remaining_args_str ~= "" and remaining_args_str or nil)
		end,
		edit = function()
			if #remaining_args == 0 then
				M.edit()
			else
				terminal.run(cmd)
			end
		end,
		new = function()
			M.new({ show_log = true, args = remaining_args_str, with_input = false })
		end,
		rebase = function()
			M.rebase()
		end,
		undo = function()
			M.undo()
		end,
		redo = function()
			M.redo()
		end,
		log = function()
			M.log({ raw_flags = remaining_args_str ~= "" and remaining_args_str or nil })
		end,
		diff = function()
			M.diff({ current = false })
		end,
		status = function()
			M.status()
		end,
		st = function()
			M.status()
		end,
	}

	if handlers[subcommand] then
		handlers[subcommand]()
	else
		terminal.run(cmd)
	end
end

-- Handle J command with subcommands and direct jj passthrough
--- @param opts table Command options from nvim_create_user_command
local function handle_j_command(opts)
	M.j(opts.fargs)
end

-- Register the J and Jdiff commands

function M.register_command()
	vim.api.nvim_create_user_command("J", handle_j_command, {
		nargs = "*",
		complete = function(arglead, _, _)
			local subcommands = {
				"log",
				"status",
				"st",
				"diff",
				"describe",
				"new",
				"squash",
				"bookmark",
				"edit",
				"abandon",
				"b",
				"git",
				"rebase",
				"abandon",
				"undo",
				"redo",
			}
			local matches = {}
			for _, cmd in ipairs(subcommands) do
				if cmd:match("^" .. vim.pesc(arglead)) then
					table.insert(matches, cmd)
				end
			end
			return matches
		end,
		desc = "Execute jj commands with subcommand support",
	})

	local function create_diff_command(name, fn, desc)
		vim.api.nvim_create_user_command(name, function(opts)
			local rev = opts.fargs[1]
			if rev then
				fn({ rev = rev })
			else
				fn()
			end
		end, { nargs = "?", desc = desc .. " (optionally pass jj revision)" })
	end

	create_diff_command("Jdiff", diff.open_vdiff, "Vertical diff against jj revision")
	create_diff_command("Jhdiff", diff.open_hdiff, "Horizontal diff against jj revision")
	create_diff_command("Jvdiff", diff.open_vdiff, "Vertical diff against jj revision")
end

return M
