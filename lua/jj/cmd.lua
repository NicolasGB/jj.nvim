--- @class jj.cmd
local M = {}

local utils = require("jj.utils")
local runner = require("jj.core.runner")
local parser = require("jj.core.parser")
local terminal = require("jj.ui.terminal")
local editor = require("jj.ui.editor")
local diff = require("jj.diff")

-- Config for cmd module
--- @class jj.cmd.opts
M.config = {
	--- @type "buffer"|"input" Editor mode for describe command: "buffer" (Git-style editor) or "input" (simple input prompt)
	describe_editor = "buffer", -- "buffer" or "input"
}

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

	-- Use buffer editor mode
	if M.config.describe_editor == "buffer" then
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

		local text = { old_description }
		table.insert(text, "") -- Empty line to separate from user input
		table.insert(text, "JJ: Change ID: " .. revset)
		table.insert(text, "JJ: This commit contains the following changes:")
		for _, item in ipairs(status_files) do
			table.insert(text, string.format("JJ:     %s %s", item.status, item.file))
		end
		table.insert(text, "JJ:") -- blank line
		table.insert(text, 'JJ: Lines starting with "JJ:" (like this one) will be removed')

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
		end)
		terminal.close_terminal_buffer()
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
		terminal.run(cmd)
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

--- @class jj.cmd.log_opts
--- @field summary? boolean
--- @field reversed? boolean
--- @field no_graph? boolean
--- @field limit? uinteger
--- @field revisions? string

local default_log_opts = { summary = false, reversed = false, no_graph = false, limit = 20 }

-- Jujutsu log
--- @param opts? jj.cmd.log_opts
function M.log(opts)
	if not utils.ensure_jj() then
		return
	end

	local cmd = "jj log"
	local merged_opts = vim.tbl_extend("force", default_log_opts, opts or {})

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

	terminal.run(cmd)
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
