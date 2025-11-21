--- @class jj.cmd
local M = {}

local utils = require("jj.utils")
local runner = require("jj.core.runner")
local parser = require("jj.core.parser")
local terminal = require("jj.ui.terminal")
local editor = require("jj.ui.editor")
local diff = require("jj.diff")

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
			checkout = "<CR>",
			checkout_immutable = "<S-CR>",
			describe = "d",
			diff = "<S-d>",
			edit = "e",
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

-- Resolve_keymaps_from_specifications
--- @param cfg table<string, string|string[]> The keymap configuration
--- @param specs table<string, { desc: string, handler: function|string, args: table }> The keymap
--- @return jj.core.buffer.keymap[]
local function resolve_keymaps_from_specs(cfg, specs)
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
local function close_keymaps()
	local cfg = M.config.keymaps.close or {}

	return resolve_keymaps_from_specs({ close = cfg }, {
		close = {
			desc = "Close buffer",
			handler = terminal.close_terminal_buffer,
		},
	})
end

--- @class jj.cmd.describe_opts
--- @field with_status boolean: Whether or not `jj st` should be displayed in a buffer while describing the commit
--- @type jj.cmd.describe_opts
local default_describe_opts = {
	with_status = true,
}

--- Execute jj describe command with the given description
--- @param description string The description text
--- @param revset? string The revision to describe
local function execute_describe(description, revset)
	if not description or description == "" then
		utils.notify("Description cannot be empty", vim.log.levels.ERROR)
		return
	end

	local cmd = "jj describe"
	if revset then
		cmd = cmd .. " -r " .. revset
	end
	cmd = cmd .. " --stdin"

	-- Use --stdin to properly handle multi-line and special characters
	local _, success = runner.execute_command(cmd, "Failed to describe", description)
	if success then
		utils.notify("Description set.", vim.log.levels.INFO)
	end
end

-- Jujutsu describe
--- @param description? string Optional description text
--- @param revset? string The revision to describe
--- @param opts? jj.cmd.describe_opts Optional command options
function M.describe(description, revset, opts)
	if not utils.ensure_jj() then
		return
	end

	-- Check if a description was provided otherwise require for input
	if description then
		-- Description provided directly
		execute_describe(description, revset)
		return
	end

	if not revset then
		revset = "@"
	end

	-- Resolve describe editor keymaps from config
	local function describe_editor_keymaps()
		local cfg = M.config.describe.editor.keymaps or {}
		return resolve_keymaps_from_specs(cfg, {
			close = {
				desc = "Close describe editor without saving",
				handler = "<cmd>close!<CR>",
			},
		})
	end

	-- Use buffer editor mode (defaults to "buffer" if not configured)
	local editor_mode = M.config.describe.editor.type or "buffer"
	if editor_mode == "buffer" then
		local cmd = "jj log -r " .. revset .. " --no-graph -T 'coalesce(description, \"\n\")'"
		local old_description_raw, success = runner.execute_command(cmd, "Failed to get old description")
		if not old_description_raw or not success then
			return
		end

		local log_cmd = "jj log -r " .. revset .. " --no-graph -T 'self.diff().summary()'"
		local status_result, success2 = runner.execute_command(log_cmd, "Error getting status")
		if not success2 then
			return
		end

		local status_files = parser.get_status_files(status_result)
		local old_description = vim.trim(old_description_raw)

		-- Split description into lines to preserve multiline descriptions
		local description_lines = vim.split(old_description, "\n")
		local text = {}
		for _, line in ipairs(description_lines) do
			table.insert(text, line)
		end
		table.insert(text, "") -- Empty line to separate from user input
		table.insert(text, "JJ: Change ID: " .. revset)
		table.insert(text, "JJ: This commit contains the following changes:")
		for _, item in ipairs(status_files) do
			table.insert(text, string.format("JJ:     %s %s", item.status, item.file))
		end
		table.insert(text, "JJ:") -- blank line
		table.insert(text, 'JJ: Lines starting with "JJ:" (like this one) will be removed')

		-- Check if we're coming from the log view so we can reopen it after editing
		local open_log_on_close = terminal.state.buf_cmd == "log"

		-- Close the terminal buffer before opening editor
		terminal.close_terminal_buffer()

		editor.open_editor(text, function(buf_lines)
			local user_lines = {}
			for _, line in ipairs(buf_lines) do
				if not line:match("^JJ:") then
					table.insert(user_lines, line)
				end
			end
			-- Join lines and trim leading/trailing whitespace
			local trimmed_description = table.concat(user_lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
			execute_describe(trimmed_description, revset)
			-- Once editing is done, reopen the log if we came from there
		end, function()
			if open_log_on_close then
				vim.schedule(function()
					vim.o.lazyredraw = true
					M.log({})
					vim.o.lazyredraw = false
					vim.cmd("redraw!")
				end)
			end
		end, describe_editor_keymaps())
	else
		-- Use input mode
		local merged_opts = vim.tbl_deep_extend("force", default_describe_opts, opts or {})
		if merged_opts.with_status then
			-- Show the status in a terminal buffer
			M.status()
		end

		vim.ui.input({
			prompt = "Description: ",
			default = "",
		}, function(input)
			-- If the user inputed something, execute the describe command
			if input then
				execute_describe(input, revset)
			end
			-- Close the current terminal when finished
			terminal.close_terminal_buffer()
		end)
	end
end

--- Handle restoring a file from the jj status buffer
--- Supports both renamed and non-renamed files
local function handle_status_restore()
	local file_info = parser.parse_file_info_from_status_line(vim.api.nvim_get_current_line())
	if not file_info then
		return
	end

	if file_info.is_rename then
		-- For renamed files, remove the new file and restore the old one from parent revision
		local rm_cmd = "rm " .. vim.fn.shellescape(file_info.new_path)
		local restore_cmd = "jj restore --from @- " .. vim.fn.shellescape(file_info.old_path)

		local _, rm_success = runner.execute_command(rm_cmd, "Failed to remove renamed file")
		if rm_success then
			local _, restore_success = runner.execute_command(restore_cmd, "Failed to restore original file")
			if restore_success then
				utils.notify(
					"Reverted rename: " .. file_info.new_path .. " -> " .. file_info.old_path,
					vim.log.levels.INFO
				)
				require("jj.cmd").status()
			end
		end
	else
		-- For non-renamed files, use regular restore
		local restore_cmd = "jj restore " .. vim.fn.shellescape(file_info.old_path)

		local _, success = runner.execute_command(restore_cmd, "Failed to restore")
		if success then
			utils.notify("Restored: " .. file_info.old_path, vim.log.levels.INFO)
			require("jj.cmd").status()
		end
	end
end

--- Handle opening a file from the jj status buffer
local function handle_status_enter()
	local file_info = parser.parse_file_info_from_status_line(vim.api.nvim_get_current_line())

	if not file_info then
		return
	end

	local filepath = file_info.new_path
	local stat = vim.uv.fs_stat(filepath)
	if not stat then
		utils.notify("File not found: " .. filepath, vim.log.levels.ERROR)
		return
	end

	-- Go to the previous window (split above)
	vim.cmd("wincmd p")

	-- Open the file in that window, replacing current buffer
	vim.cmd("edit " .. vim.fn.fnameescape(filepath))
end

-- Resolve status keymaps from config, filtering out nil values
--- @return jj.core.buffer.keymap[]
local function status_keymaps()
	local cfg = M.config.keymaps.status or {}
	local specs = {
		open_file = {
			desc = "Open file under cursor",
			handler = handle_status_enter,
		},
		restore_file = {
			desc = "Restore file under cursor",
			handler = handle_status_restore,
		},
	}

	return resolve_keymaps_from_specs(cfg, specs)
end

-- Jujutsu status.
function M.status(opts)
	if not utils.ensure_jj() then
		return
	end

	local cmd = "jj st"

	if opts and opts.notify then
		local output, success = runner.execute_command(cmd, "Failed to get status")
		if success then
			utils.notify(output and output or "", vim.log.levels.INFO)
		end
	else
		-- Default behavior: show in buffer
		local keymaps = { unpack(status_keymaps()), unpack(close_keymaps()) }
		terminal.run(cmd, keymaps)
	end
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
local function handle_log_new(flag, ignore_immut)
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
local function handle_log_diff()
	local line = vim.api.nvim_get_current_line()
	local revset = parser.get_rev_from_log_line(line)

	if revset then
		local cmd = string.format("jj show %s", revset)
		terminal.run_floating(cmd)
	else
		utils.notify("No valid revision found in the log line", vim.log.levels.ERROR)
	end
end

--- Handle describing a log line
local function handle_log_describe()
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
local function handle_log_enter(ignore_immut)
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
--- @return table<string, string|string[]>
local function log_keymaps()
	-- Reduce repetition by declaring a specification table.
	-- Each entry maps the config key name to:
	--   desc: human description
	--   handler: function to call
	--   args: optional list of arguments passed to handler
	local cfg = M.config.keymaps.log or {}

	local specs = {
		close = {
			desc = "Close log buffer",
			handler = terminal.close_terminal_buffer,
		},
		checkout = {
			desc = "Checkout revision under cursor",
			handler = handle_log_enter,
			args = { false },
		},
		checkout_immutable = {
			desc = "Checkout revision under cursor (ignores immutability)",
			handler = handle_log_enter,
			args = { true },
		},
		describe = {
			desc = "Describe revision under cursor",
			handler = handle_log_describe,
		},
		diff = {
			desc = "Diff revision under cursor",
			handler = handle_log_diff,
		},
		edit = {
			desc = "Edit revision under cursor",
			handler = handle_log_enter,
			args = { false },
		},
		new = {
			desc = "Create new change branching off revision under cursor",
			handler = handle_log_new,
			args = { nil, false },
		},
		new_after = {
			desc = "Create new change after revision under cursor",
			handler = handle_log_new,
			args = { "after", false },
		},
		new_after_immutable = {
			desc = "Create new change after revision under cursor (ignore immutable)",
			handler = handle_log_new,
			args = { "after", true },
		},
		undo = {
			desc = "Undo last change",
			handler = M.undo,
		},
		redo = {
			desc = "Redo last undone change",
			handler = M.redo,
		},
	}

	return resolve_keymaps_from_specs(cfg, specs)
end

--- @class jj.cmd.log_opts
--- @field summary? boolean
--- @field reversed? boolean
--- @field no_graph? boolean
--- @field limit? uinteger
--- @field revisions? string
--- @field raw_flags? string

---@type jj.cmd.log_opts
local default_log_opts = { summary = false, reversed = false, no_graph = false, limit = 20, raw_flats = nil }

-- Jujutsu log
--- @param opts? jj.cmd.log_opts
function M.log(opts)
	if not utils.ensure_jj() then
		return
	end

	local cmd = "jj log"
	local merged_opts = vim.tbl_extend("force", default_log_opts, opts or {})

	-- If a raw has been given simply execute it as is
	if merged_opts.raw then
		return terminal.run(string.format("%s %s", cmd, merged_opts.raw), log_keymaps())
	end

	for key, value in pairs(merged_opts) do
		key = key:gsub("_", "-")
		if key == "limit" and value then
			cmd = string.format("%s --%s %d", cmd, key, value)
		elseif key == "revisions" and value then
			cmd = string.format("%s --%s %s", cmd, key, value)
		elseif value then
			cmd = string.format("%s --%s", cmd, key)
		end
	end

	terminal.run(cmd, log_keymaps())
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
