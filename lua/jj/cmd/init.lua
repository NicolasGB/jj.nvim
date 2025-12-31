--- @class jj.cmd
local M = {}

local utils = require("jj.utils")
local runner = require("jj.core.runner")
local parser = require("jj.core.parser")
local terminal = require("jj.ui.terminal")

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

--- @class jj.cmd.log
--- @field close_on_edit? boolean Whether to close the log buffer when editing a change

--- @class jj.cmd.log.keymaps
--- @field edit? string|string[] Keymaps for the log command buffer, setting a keymap to nil will disable it
--- @field edit_immutable? string|string[]
--- @field describe? string|string[]
--- @field diff? string|string[]
--- @field new? string|string[]
--- @field new_after? string|string[]
--- @field new_after_immutable? string|string[]
--- @field undo? string|string[]
--- @field redo? string|string[]
--- @field abandon? string|string[]
--- @field fetch? string|string[]
--- @field push_all? string|string[]
--- @field push? string|string[]
--- @field open_pr? string|string[]
--- @field open_pr_list? string|string[]
--- @field bookmark? string|string[]
--- @field rebase_mode? jj.cmd.rebase.keymaps

--- @class jj.cmd.rebase.keymaps
--- @field onto? string|string[]
--- @field after? string|string[]
--- @field before? string|string[]
--- @field exit_mode? string|string[]

--- @class jj.cmd.bookmark
--- @field prefix? string Prefix to append when creating a bookmark

--- @class jj.cmd.status.keymaps
--- @field open_file? string|string[] Keymaps for the status command buffer, setting a keymap to nil will disable it
--- @field restore_file? string|string[]

--- @class jj.cmd.floating.keymaps The floating buffer is the one shown when diffing from the log buffer
--- @field close? string|string[] Keymaps to close the floating buffer
--- @field hide? string|string[] Keymaps to hide the floating buffer

--- @class jj.cmd.keymaps
--- @field log? jj.cmd.log.keymaps Keymaps for the log command buffer
--- @field status? jj.cmd.status.keymaps Keymaps for the status command buffer
--- @field close? string|string[] Keymaps for the close keybind
--- @field floating? jj.cmd.floating.keymaps Keymaps for the floating buffer

--- @class jj.cmd.opts
--- @field describe? jj.cmd.describe
--- @field log? jj.cmd.log
--- @field bookmark? jj.cmd.bookmark
--- @field keymaps? jj.cmd.keymaps Keymaps for the buffers containing the  of the commands
---
--- @class jj.cmd.keymap_spec
--- @field desc string
--- @field handler function|string
--- @field args? table

--- @alias jj.cmd.keymap_specs table<string, jj.cmd.keymap_spec>

--- @class jj.cmd.push_opts
--- @field bookmark? string Specific bookmark to push (default: all)

--- @class jj.cmd.open_pr_opts
--- @field list_bookmarks? boolean Whether to select from all bookmarks instead of current revision

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
	log = {
		close_on_edit = false,
	},
	bookmark = {
		prefix = "",
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
			abandon = "a",
			fetch = "f",
			push_all = "<S-P>",
			push = "p",
			open_pr = "o",
			open_pr_list = "<S-o>",
			bookmark = "b",
			rebase = "r",
			rebase_mode = {
				onto = { "<CR>", "o" },
				after = { "a", "A" },
				before = { "b", "B" },
				exit_mode = { "<Esc>", "<C-c>" },
			},
		},
		status = {
			open_file = "<CR>",
			restore_file = "<S-x>",
		},
		close = { "q", "<Esc>" },
		floating = {
			close = "q",
			hide = "<Esc>",
		},
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
			-- Create the handler, wrapping it with args if provided
			local handler = spec.handler
			if spec.args then
				handler = function()
					spec.handler(unpack(spec.args))
				end
			end

			if type(lhs) == "table" then
				for _, key_lhs in ipairs(lhs) do
					table.insert(keymaps, { modes = "n", lhs = key_lhs, rhs = handler, opts = { desc = spec.desc } })
				end
			else
				table.insert(keymaps, { modes = "n", lhs = lhs, rhs = handler, opts = { desc = spec.desc } })
			end
		end
	end

	return keymaps
end

-- Resolve terminal keymaps from config
--- @return jj.core.buffer.keymap[]
function M.terminal_keymaps()
	local cfg = M.config.keymaps.close or {}

	return M.resolve_keymaps_from_specs({ close = cfg }, {
		close = {
			desc = "Close buffer",
			handler = terminal.close_terminal_buffer,
		},
	})
end

-- Resolve floating keymaps from config
--- @return jj.core.buffer.keymap[]
function M.floating_keymaps()
	local cfg = M.config.keymaps.floating or {}

	return M.resolve_keymaps_from_specs(cfg, {
		close = {
			desc = "Close floating buffer",
			handler = terminal.close_floating_buffer,
		},
		hide = {
			desc = "Hide floating buffer",
			handler = terminal.hide_floating_buffer,
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
		runner.execute_command_async(cmd, function()
			utils.notify("Command `new` was succesful.", vim.log.levels.INFO)
			-- Show the updated log if the user requested it
			if opts.show_log then
				M.log()
			end
		end, "Failed to create new change")
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
			runner.execute_command_async(string.format("jj edit %s", input), function()
				M.log({})
			end, "Error editing change")
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
	runner.execute_command_async(cmd, function()
		utils.notify("Command `squash` was succesful.", vim.log.levels.INFO)
		if terminal.state.buf_cmd == "log" then
			M.log()
		end
	end, "Failed to squash")
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

	terminal.run(cmd, M.terminal_keymaps())
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
			runner.execute_command_async(cmd, function()
				utils.notify("Rebase successful.", vim.log.levels.INFO)
				M.log({})
			end, "Error rebasing")
		else
			terminal.close_terminal_buffer()
		end
	end)
end

-- Jujutsu create bookmark
--- @param opts? jj.cmd.bookmark The options for the bookmark command
function M.bookmark_create(opts)
	if not utils.ensure_jj() then
		return
	end

	-- Try and get the bookmark from the params
	local bookmark_prefix = (opts and opts.prefix) or (M.config.bookmark and M.config.bookmark.prefix) or ""

	M.log({})
	vim.ui.input({
		prompt = "Bookmark name: ",
		default = bookmark_prefix,
	}, function(input)
		if input then
			-- Get the revset
			vim.ui.input({
				prompt = "Revset (default: @): ",
				default = "@",
			}, function(revset)
				revset = revset or "@"
				local cmd = string.format("jj b c %s -r %s", input, revset)
				runner.execute_command_async(cmd, function()
					utils.notify(
						string.format("Bookmark `%s` created successfully for %s", input, revset),
						vim.log.levels.INFO
					)
					M.log({})
				end, "Error creating bookmark")
			end)
		else
			terminal.close_terminal_buffer()
		end
	end)
end

-- Jujutsu bookmark move
function M.bookmark_move()
	if not utils.ensure_jj() then
		return
	end
	M.log({})
	local bookmarks = utils.get_all_bookmarks()
	if #bookmarks == 0 then
		utils.notify("No bookmarks found to move", vim.log.levels.ERROR)
		return
	end

	vim.ui.select(bookmarks, {
		prompt = "Select bookmark to move: ",
	}, function(choice)
		if choice then
			vim.ui.input({
				prompt = "New revset for bookmark '" .. choice .. "': ",
				default = "@",
			}, function(revset)
				if revset then
					local cmd = string.format("jj b m %s --to %s", choice, revset)
					runner.execute_command_async(cmd, function()
						utils.notify(
							string.format("Bookmark `%s` moved successfully to %s", choice, revset),
							vim.log.levels.INFO
						)
						M.log({})
					end, "Error moving bookmark")
				else
					terminal.close_terminal_buffer()
				end
			end)
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
			runner.execute_command_async(cmd, function()
				utils.notify(string.format("Bookmark `%s` deleted successfully.", input), vim.log.levels.INFO)
				M.log({})
			end, "Error deleting bookmark")
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
	runner.execute_command_async(cmd, function()
		utils.notify("Command `undo` was succesful.", vim.log.levels.INFO)
		if terminal.state.buf_cmd == "log" then
			M.log({})
		end
	end, "Failed to undo")
end

-- Jujutsu redo
function M.redo()
	if not utils.ensure_jj() then
		return
	end

	local cmd = "jj redo"
	runner.execute_command_async(cmd, function()
		utils.notify("Command `redo` was succesful.", vim.log.levels.INFO)
		if terminal.state.buf_cmd == "log" then
			M.log({})
		end
	end, "Failed to redo")
end

-- Jujutsu abandon
function M.abandon()
	if not utils.ensure_jj() then
		return
	end

	M.log({})
	vim.ui.input({
		prompt = "Change to abandon: ",
		default = "",
	}, function(input)
		if input then
			local cmd = string.format("jj abandon %s", input)
			runner.execute_command_async(cmd, function()
				utils.notify("Change abandoned successfully.", vim.log.levels.INFO)
				M.log({})
			end, "Error abandoning change")
		else
			terminal.close_terminal_buffer()
		end
	end)
end

-- Jujutsu fetch
function M.fetch()
	if not utils.ensure_jj() then
		return
	end

	-- Save the lop one state to refresh
	local log_open = terminal.state.buf_cmd == "log"

	-- Get the list of remotes
	local remotes = utils.get_remotes()
	if not remotes or #remotes == 0 then
		utils.notify("No git remotes found to fetch from", vim.log.levels.ERROR)
		return
	end

	if #remotes > 1 then
		-- Prompt to select a remote
		vim.ui.select(remotes, {
			prompt = "Select remote to fetch from: ",
			format_item = function(item)
				return string.format("%s (%s)", item.name, item.url)
			end,
		}, function(choice)
			if choice then
				local cmd = string.format("jj git fetch --remote %s", choice.name)
				runner.execute_command_async(cmd, function()
					utils.notify(string.format("Fetching from %s...", choice), vim.log.levels.INFO)
					if log_open then
						M.log({})
					end
				end, "Error fetching from remote")
			end
		end)
	else
		-- Only one remote, fetch from it directly
		local cmd = "jj git fetch"
		utils.notify("Fetching from remote...", vim.log.levels.INFO)
		runner.execute_command_async(cmd, function()
			utils.notify("Successfully fetched from remote", vim.log.levels.INFO)
			if log_open then
				M.log({})
			end
		end, "Error fetching from remote")
	end
end

-- Jujutsu push
--- @param opts? jj.cmd.push_opts Optional push options
function M.push(opts)
	if not utils.ensure_jj() then
		return
	end

	opts = opts or {}

	-- Save the lop one state to refresh
	local log_open = terminal.state.buf_cmd == "log"

	local cmd = "jj git push"
	if opts.bookmark then
		utils.notify(string.format("Pushing `%s` bookmark ...", opts.bookmark), vim.log.levels.INFO, 1000)
		cmd = string.format("%s --bookmark %s", cmd, opts.bookmark)
	else
		utils.notify(string.format("Pushing `ALL` bookmarks...", opts.bookmark), vim.log.levels.INFO, 1000)
	end

	runner.execute_command_async(cmd, function()
		utils.notify("Successfully pushed to remote", vim.log.levels.INFO)
		if log_open then
			M.log({})
		end
	end, "Error pushing to remote")
end

--- Open a PR on the remote from the current change's bookmark
--- @param opts? jj.cmd.open_pr_opts Options for opening PR
function M.open_pr(opts)
	if not utils.ensure_jj() then
		return
	end

	opts = opts or {}

	if opts.list_bookmarks then
		-- Get all bookmarks
		local bookmarks = utils.get_all_bookmarks()

		if #bookmarks == 0 then
			utils.notify("No bookmarks found", vim.log.levels.ERROR)
			return
		end

		-- Prompt to select a bookmark
		vim.ui.select(bookmarks, {
			prompt = "Select bookmark to open PR for: ",
		}, function(choice)
			if choice then
				utils.open_pr_for_bookmark(choice)
			end
		end)
		-- Return early
		return
	end

	-- Get the bookmark from the current change (@)
	local bookmark, success =
		runner.execute_command("jj log -r @ --no-graph -T 'bookmarks'", "Failed to get current bookmark", nil, true)

	if not success or not bookmark or bookmark:match("^%s*$") then
		-- If no bookmark on @, try @-
		bookmark, success =
			runner.execute_command("jj log -r @- --no-graph -T 'bookmarks'", "Failed to get parent bookmark", nil, true)

		if not success or not bookmark or bookmark:match("^%s*$") then
			utils.notify("No bookmark found on @ or @- commits. Cannot open PR.", vim.log.levels.ERROR)
			return
		end
	end

	-- Trim and remove asterisks from bookmark
	bookmark = bookmark:match("^%*?(.-)%*?$"):gsub("%s+", "")

	-- Open the PR using the utility function
	utils.open_pr_for_bookmark(bookmark)
end

--- @param args string|string[] jj command arguments
function M.j(args)
	if not utils.ensure_jj() then
		return
	end

	local cmd = nil
	if #args == 0 then
		local default_cmd_str, success = runner.execute_command(
			"jj config get ui.default-command",
			"Error getting user's default command",
			nil,
			true
		)
		if not success then
			terminal.run("jj", M.terminal_keymaps())
			return
		end

		local default_cmd = parser.parse_default_cmd(default_cmd_str and default_cmd_str or "")
		if default_cmd == nil then
			terminal.run("jj", M.terminal_keymaps())
			return
		end
		cmd = default_cmd
	end

	if type(args) == "string" then
		cmd = vim.split(args, "%s+")
	elseif cmd == nil then
		-- If a cmd hasn't been parsed make the cmd the whole args
		cmd = args
	end

	local subcommand = cmd[1]
	local remaining_args = vim.list_slice(cmd, 2)
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
				terminal.run(cmd, M.terminal_keymaps())
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
		abandon = function()
			M.abandon()
		end,
		push = function()
			if #remaining_args > 0 then
				M.push({ bookmark = remaining_args[1] })
			else
				M.push()
			end
		end,
		fetch = function()
			M.fetch()
		end,
		open_pr = function()
			if remaining_args_str:match("--list") then
				M.open_pr({ list_bookmarks = true })
			else
				M.open_pr()
			end
		end,
		bookmark = function()
			if remaining_args[1] == "create" or remaining_args[1] == "c" then
				M.bookmark_create()
			elseif remaining_args[1] == "move" or remaining_args[1] == "m" then
				M.bookmark_move()
			elseif remaining_args[1] == "delete" or remaining_args[1] == "d" then
				M.bookmark_delete()
			else
				terminal.run(cmd, M.terminal_keymaps())
			end
		end,
		annotate = function()
			require("jj.annotate").file()
		end,
		annotate_line = function()
			require("jj.annotate").line()
		end,
	}

	if handlers[subcommand] then
		handlers[subcommand]()
	else
		-- Prepend 'jj' if cmd is an array and doesn't already start with it
		if type(cmd) == "table" and cmd[1] ~= "jj" then
			table.insert(cmd, 1, "jj")
		end
		terminal.run(cmd, M.terminal_keymaps())
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
				"abandon",
				"b",
				"bookmark",
				"describe",
				"diff",
				"edit",
				"fetch",
				"git",
				"log",
				"new",
				"push",
				"rebase",
				"redo",
				"squash",
				"st",
				"status",
				"undo",
				"open_pr",
				"annotate",
				"annotate_line",
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
