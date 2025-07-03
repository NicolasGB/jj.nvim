--- @class jj.cmd
local M = {}

local utils = require("jj.utils")

local state = {
	-- The current terminal buffer for jj commands
	--- @type integer|nil
	buf = nil,

	-- The current channel to communciate with the terminal
	--- @type integer|nil
	chan = nil,
	--- The current job id for the terminal buffer
	--- @type integer|nil
	job_id = nil,
}

--- Close the current terminal buffer if it exists
local function close_terminal_buffer()
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		vim.cmd("bwipeout! " .. state.buf)
	else
		vim.cmd("close")
	end
end

--- Handle Enter key press on jj status buffer
local function handle_status_enter()
	local line = vim.api.nvim_get_current_line()
	-- jj status format: "M filename" or "A filename" or "D filename" etc.
	-- Match lines that start with status letter followed by space and filename
	local pattern = "^[MADR?!] (.+)$"
	local filepath = line:match(pattern)

	if not filepath or filepath == "" then
		return
	end

	local stat = vim.loop.fs_stat(filepath)
	if not stat then
		utils.notify("File not found: " .. filepath, vim.log.levels.ERROR)
		return
	end

	-- Go to the previous window (split above)
	vim.cmd("wincmd p")

	-- Open the file in that window, replacing current buffer
	vim.cmd("edit " .. vim.fn.fnameescape(filepath))
end

--- Run a command and show it's output in a terminal buffer
--- If a previous command already existed it smartly reuses the buffer cleaning the previous output
---@param cmd string
local function run(cmd)
	-- Clean up previous state if invalid
	if state.buf and not vim.api.nvim_buf_is_valid(state.buf) then
		state.buf = nil
		state.chan = nil
		state.job_id = nil
	end

	-- Stop any running job first
	if state.job_id then
		vim.fn.jobstop(state.job_id)
		state.job_id = nil
	end

	-- Close previous channel
	if state.chan then
		vim.fn.chanclose(state.chan)
		state.chan = nil
	end

	local win
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		-- Find or create a window for the buffer
		local buf_wins = vim.fn.win_findbuf(state.buf)
		if #buf_wins > 0 then
			vim.api.nvim_set_current_win(buf_wins[1])
			win = buf_wins[1]
		else
			vim.cmd("split")
			win = vim.api.nvim_get_current_win()
			vim.api.nvim_win_set_buf(win, state.buf)
		end
	else
		-- Create new terminal buffer
		vim.cmd("split")
		win = vim.api.nvim_get_current_win()
		state.buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_win_set_buf(win, state.buf)

		-- Set buffer options only once
		vim.bo[state.buf].bufhidden = "wipe"
	end

	-- Create new terminal channel
	local chan = vim.api.nvim_open_term(state.buf, {})
	if not chan or chan <= 0 then
		vim.notify("Failed to create terminal channel", vim.log.levels.ERROR)
		return
	end
	state.chan = chan

	-- Clear terminal before running new command
	vim.api.nvim_chan_send(chan, "\27[H\27[2J")

	local jid = vim.fn.jobstart(cmd, {
		pty = true,
		width = vim.api.nvim_win_get_width(win),
		height = vim.api.nvim_win_get_height(win),
		env = {
			TERM = "xterm-256color",
			PAGER = "cat",
			DELTA_PAGER = "cat",
			COLORTERM = "truecolor",
		},
		on_stdout = function(_, data)
			if not vim.api.nvim_buf_is_valid(state.buf) or not state.chan then
				return
			end
			local output = table.concat(data, "\n")
			vim.api.nvim_chan_send(state.chan, output)
		end,
		on_exit = function(_, _)
			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(state.buf) then
					vim.bo[state.buf].modifiable = false
					if vim.api.nvim_get_current_buf() == state.buf then
						vim.cmd("stopinsert")
					end
				end
			end)
		end,
	})

	if jid <= 0 then
		vim.api.nvim_chan_send(chan, "Failed to start command: " .. cmd .. "\r\n")
		state.chan = nil
	else
		state.job_id = jid
	end

	-- Set keymaps only if they haven't been set for this buffer
	if not vim.b[state.buf].jj_keymaps_set then
		vim.keymap.set({ "n", "v" }, "i", function() end, { buffer = state.buf, noremap = true, silent = true })
		vim.keymap.set({ "n", "v" }, "c", function() end, { buffer = state.buf, noremap = true, silent = true })
		vim.keymap.set({ "n", "v" }, "a", function() end, { buffer = state.buf, noremap = true, silent = true })
		vim.keymap.set({ "n", "v" }, "q", close_terminal_buffer, { buffer = state.buf, noremap = true, silent = true })
		vim.keymap.set({ "n" }, "<ESC>", close_terminal_buffer, { buffer = state.buf, noremap = true, silent = true })

		-- Add Enter key mapping for status buffers to open files
		local cmd_parts = vim.split(cmd, " ")
		if cmd_parts[2] == "st" or cmd_parts[2] == "status" then
			vim.keymap.set({ "n" }, "<CR>", handle_status_enter, { buffer = state.buf, noremap = true, silent = true })
		end

		vim.b[state.buf].jj_keymaps_set = true
	end

	vim.cmd("stopinsert")

	-- Set up cleanup autocmd only once per buffer
	if not vim.b[state.buf].jj_cleanup_set then
		vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
			buffer = state.buf,
			callback = function()
				if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
					state.buf = nil
				end
				if state.chan then
					vim.fn.chanclose(state.chan)
					state.chan = nil
				end
				if state.job_id then
					vim.fn.jobstop(state.job_id)
					state.job_id = nil
				end
			end,
		})
		vim.b[state.buf].jj_cleanup_set = true
	end
end

--- Execute jj describe command with the given description
---@param description string The description text
local function execute_describe(description)
	if not description or description == "" then
		utils.notify("Description cannot be empty", vim.log.levels.ERROR)
		return
	end

	local cmd = string.format("jj describe -m '%s'", description)
	local _, success = utils.execute_command(cmd, "Failed to describe")
	if not success then
		return
	else
		utils.notify("Description set.", vim.log.levels.INFO)
	end
end

--- @class jj.cmd.describe_opts
--- @field with_status boolean: Whether or not `jj st` should be displayed in a buffer while describing the commit

--- @type jj.cmd.describe_opts
local default_describe_opts = {
	with_status = true,
}

--- Jujutsu describe
---@param description? string Optional description text
---@param opts? jj.cmd.describe_opts Optional command options
function M.describe(description, opts)
	if not utils.ensure_jj() then
		return
	end

	-- Check if a description was provided otherwise require for input
	if not description then
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
				execute_describe(input)
			end
			-- Close the current terminal when finished
			close_terminal_buffer()
		end)
	end
end

--- Jujutsu status
function M.status()
	if not utils.ensure_jj() then
		return
	end

	local cmd = "jj st"
	run(cmd)
end

--- @class jj.cmd.new_opts
--- @field show_log boolean Whether or not to display the log command after creating a new
--- @field with_input boolean Whether or not to use nvim input to decide the parent of the new commit
--- @field args string The arguments to append to the new command

--- Jujutsu new
---@param opts jj.cmd.new_opts|nil
function M.new(opts)
	if not utils.ensure_jj() then
		return
	end

	---@param cmd string
	local function execute_new(cmd)
		utils.execute_command(cmd, "Failed to create new change")
		utils.notify("Command `new` was succesful.", vim.log.levels.INFO)
		-- Show the updated log if the user requested it
		if opts and opts.show_log then
			M.log()
		end
	end

	-- If the user wants use input mode
	if opts and opts.with_input then
		if opts.show_log then
			M.log()
		end

		vim.ui.input({
			prompt = "Parent(s) of the new change [default: @]",
		}, function(input)
			if input then
				execute_new(string.format("jj new %s", input))
			end
			close_terminal_buffer()
		end)
	else
		-- Otherwise follow a classic flow for inputing
		local cmd = "jj new"
		if opts and opts.args then
			cmd = string.format("jj new %s", opts.args)
		end

		execute_new(cmd)
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
		-- If the user inputed something, execute the describe command
		if input then
			local _, success = utils.execute_command(string.format("jj edit %s", input), "Error editing change")
			if not success then
				return
			end

			-- If ok update the log window
			M.log({})
		else
			-- If user exited without saving discard the log
			close_terminal_buffer()
		end
	end)
end

--- Jujutsu squash
function M.squash()
	if not utils.ensure_jj() then
		return
	end

	local cmd = "jj squash"
	local _, success = utils.execute_command(cmd, "Failed to squash")
	if success then
		utils.notify("Command `squash` was succesful.", vim.log.levels.INFO)
	end
end

---@class jj.cmd.log_opts
---@field summary? boolean: Show a summary of the log
---@field reversed? boolean: Show the log in reverse order
---@field no_graph? boolean: Do not show the graph in the log output
---@field limit? uinteger : Limit the number of log entries shown, defaults to 20 if not provided
---@field revisions? string: Which revisions to show

--- @type jj.cmd.log_opts
local default_log_opts = {
	--- @type boolean
	summary = false,
	--- @type boolean
	reversed = false,
	--- @type boolean
	no_graph = false,
	--- @type uinteger
	limit = 20,
}
--- Jujutsu log
---@param opts jj.cmd.log_opts|nil Command options from nvim_create_user_command
function M.log(opts)
	if not utils.ensure_jj() then
		return
	end

	local cmd = "jj log"

	-- Merge default options with provided ones
	local merged_opts = vim.tbl_extend("force", default_log_opts, opts or {})

	-- Add options to the command
	for key, value in pairs(merged_opts) do
		-- Replace _ with - for command line options
		key = key:gsub("_", "-")

		-- Handle special cases such as limit
		if key == "limit" and value then
			cmd = string.format("%s --%s %d", cmd, key, value)
		elseif key == "revisions" and value then
			cmd = string.format("%s --%s %s", cmd, key, value)
		elseif value then
			-- Simply append the option
			cmd = string.format("%s --%s", cmd, key)
		end
	end

	run(cmd)
end

--- Jujutsu diff
function M.diff()
	if not utils.ensure_jj() then
		return
	end

	local cmd = "jj diff"
	run(cmd)
end

--- @param args string|string[] jj command arguments
function M.j(args)
	if not utils.ensure_jj() then
		return
	end

	if #args == 0 then
		-- Use the user's default command and do not try to parse anythng else
		run("jj")
		return
	end

	-- Check if args is a string
	if type(args) == "string" then
		-- Split the string into a table of arguments
		args = vim.split(args, "%s+")
	end

	local subcommand = args[1]
	local remaining_args = vim.list_slice(args, 2)

	local cmd_args = table.concat(args, " ")
	local cmd = string.format("jj %s", cmd_args)

	-- Handle known subcommands with custom logic
	if subcommand == "describe" then
		local description = table.concat(remaining_args, " ")
		M.describe(description ~= "" and description or nil)
		return
	elseif subcommand == "edit" and #remaining_args == 0 then
		M.edit()
		return
	elseif subcommand == "new" then
		M.new({ show_log = true, args = table.concat(remaining_args, " "), with_input = false })
		return
	end

	-- Run the command in the terminal
	run(cmd)
end

--- Handle J command with subcommands and direct jj passthrough
---@param opts table Command options from nvim_create_user_command
local function handle_j_command(opts)
	local args = opts.fargs
	M.j(args)
end

--- Register the J command
function M.register_command()
	vim.api.nvim_create_user_command("J", handle_j_command, {
		nargs = "*",
		complete = function(arglead, _, _)
			-- Basic completion for common jj subcommands
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
end

return M
