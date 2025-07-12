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

	-- The floating buffer if any
	--- @type integer|nil
	floating_buf = nil,
	-- The floating channel to communciate with the terminal
	--- @type integer|nil
	floating_chan = nil,
	--- The floating job id for the terminal buffer
	--- @type integer|nil
	floating_job_id = nil,
}

--- Close the current terminal buffer if it exists
local function close_terminal_buffer()
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		vim.cmd("bwipeout! " .. state.buf)
	else
		vim.cmd("close")
	end
end

--- Close the current terminal buffer if it exists
local function close_floating_buffer()
	if state.buf and vim.api.nvim_buf_is_valid(state.floating_buf) then
		vim.cmd("bwipeout! " .. state.floating_buf)
	else
		vim.cmd("close")
	end
end

--- Hide the current floating window
local function hide_floating_window()
	if state.floating_buf and vim.api.nvim_buf_is_valid(state.floating_buf) then
		vim.cmd("hide")
	end
end

local function parse_file_info_from_status_line()
	local line = vim.api.nvim_get_current_line()

	-- Handle renamed files: "R path/{old_name => new_name}" or "R old_path => new_path"
	local rename_pattern_curly = "^R (.*)/{(.*) => ([^}]+)}"
	local dir_path, old_name, new_name = line:match(rename_pattern_curly)

	if dir_path and old_name and new_name then
		return {
			old_path = dir_path .. "/" .. old_name,
			new_path = dir_path .. "/" .. new_name,
			is_rename = true,
		}
	else
		-- Try simple rename pattern: "R old_path => new_path"
		local rename_pattern_simple = "^R (.*) => (.+)$"
		local old_path, new_path = line:match(rename_pattern_simple)
		if old_path and new_path then
			return {
				old_path = old_path,
				new_path = new_path,
				is_rename = true,
			}
		end
	end

	-- Not a rename, try regular status patterns
	local filepath
	-- Handle renamed files: "R path/{old_name => new_name}" or "R old_path => new_path"
	local rename_pattern_curly_new = "^R (.*)/{.* => ([^}]+)}"
	local dir_path_new, renamed_file = line:match(rename_pattern_curly_new)

	if dir_path_new and renamed_file then
		filepath = dir_path_new .. "/" .. renamed_file
	else
		-- Try simple rename pattern: "R old_path => new_path"
		local rename_pattern_simple_new = "^R .* => (.+)$"
		filepath = line:match(rename_pattern_simple_new)
	end

	if not filepath then
		-- jj status format: "M filename" or "A filename"
		-- Match lines that start with status letter followed by space and filename
		local pattern = "^[MAD?!] (.+)$"
		filepath = line:match(pattern)
	end

	if filepath then
		return {
			old_path = filepath,
			new_path = filepath,
			is_rename = false,
		}
	end

	return nil
end

local function handle_status_enter()
	local file_info = parse_file_info_from_status_line()

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

local function handle_status_restore()
	local file_info = parse_file_info_from_status_line()

	if not file_info then
		return
	end

	if file_info.is_rename then
		-- For renamed files, remove the new file and restore the old one from parent revision
		local rm_cmd = "rm " .. vim.fn.shellescape(file_info.new_path)
		local restore_cmd = "jj restore --from @- " .. vim.fn.shellescape(file_info.old_path)

		local _, rm_success = utils.execute_command(rm_cmd, "Failed to remove renamed file")
		if rm_success then
			local _, restore_success = utils.execute_command(restore_cmd, "Failed to restore original file")
			if restore_success then
				utils.notify(
					"Reverted rename: " .. file_info.new_path .. " -> " .. file_info.old_path,
					vim.log.levels.INFO
				)
				M.status()
			end
		end
	else
		-- For non-renamed files, use regular restore
		local restore_cmd = "jj restore " .. vim.fn.shellescape(file_info.old_path)

		local _, success = utils.execute_command(restore_cmd, "Failed to restore")
		if success then
			utils.notify("Restored: " .. file_info.old_path, vim.log.levels.INFO)
			M.status()
		end
	end
end

--- Extract revision ID from a jujutsu log line
--- @param line string The log line to parse
--- @return string|nil The revision ID if found, nil otherwise
local function get_rev_from_log_line(line)
	-- Define jujutsu symbols with their UTF-8 byte sequences
	local jj_symbols = {
		diamond = "\226\151\134", -- ◆
		circle = "\226\151\139", -- ○
	}

	local revset

	-- Try each symbol pattern
	for _, symbol in pairs(jj_symbols) do
		-- Pattern: Lines starting with symbol
		revset = line:match("^%s*" .. symbol .. "%s+(%w+)")
		if revset then
			return revset
		end

		-- Pattern: Lines with │ followed by symbol (this are the branches)
		revset = line:match("^│%s*" .. symbol .. "%s+(%w+)")
		if revset then
			return revset
		end
	end

	-- Pattern for simple ASCII symbols
	revset = line:match("^%s*[@]%s+(%w+)")
	if revset then
		return revset
	end

	return nil
end

--- Handle keypress enter on `jj log` buffer to edit a previous revision
local function handle_log_enter()
	local line = vim.api.nvim_get_current_line()

	local revset = get_rev_from_log_line(line)

	if revset then
		-- If we found a revision, edit it
		local cmd = string.format("jj edit %s", revset)
		local _, success = utils.execute_command(cmd, "Error editing change")
		if not success then
			return
		end

		utils.notify(string.format("Editing change: `%s`", revset), vim.log.levels.INFO)
		-- Close the terminal buffer
		close_terminal_buffer()
	end
end
---
---
--- Create a floating window for terminal output
--- @param config table Window configuration options
--- @param enter boolean Whether to enter the window after creation
--- @return integer buf Buffer number
--- @return integer win Window number
local function create_floating_window(config, enter)
	local default_config = {
		width = math.floor(vim.o.columns * 0.8),
		height = math.floor(vim.o.lines * 0.8),
		row = math.floor((vim.o.lines - math.floor(vim.o.lines * 0.8)) / 2),
		col = math.floor((vim.o.columns - math.floor(vim.o.columns * 0.8)) / 2),
		relative = "editor",
		style = "minimal",
		border = "rounded",
		title = " JJ Diff ",
		title_pos = "center",
	}

	local merged_config = vim.tbl_extend("force", default_config, config or {})

	-- Create buffer
	local buf = vim.api.nvim_create_buf(false, true)

	-- Create window
	local win = vim.api.nvim_open_win(buf, enter or false, merged_config)

	-- Set buffer options
	vim.bo[buf].bufhidden = "hide"

	-- Set window options
	vim.wo[win].wrap = true
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].cursorline = false
	vim.wo[win].signcolumn = "no"

	return buf, win
end

--- Run the command in a floating window
--- @param cmd string The command to run in the floating window
local function run_floating(cmd)
	-- Clean up previous state if invalid
	if state.floating_buf and not vim.api.nvim_buf_is_valid(state.floating_buf) then
		state.floating_buf = nil
		state.floating_chan = nil
		state.floating_job_id = nil
	end

	-- Stop any running job first
	if state.floating_job_id then
		vim.fn.jobstop(state.floating_job_id)
		state.floating_job_id = nil
	end

	-- Close previous channel
	if state.floating_chan then
		vim.fn.chanclose(state.floating_chan)
		state.floating_chan = nil
	end

	local win, buf
	if state.floating_buf and vim.api.nvim_buf_is_valid(state.floating_buf) then
		-- Find or create a window for the buffer
		local buf_wins = vim.fn.win_findbuf(state.floating_buf)
		if #buf_wins > 0 then
			vim.api.nvim_set_current_win(buf_wins[1])
			win = buf_wins[1]
		else
			-- If the buffer is hidden create a new window and override the buffer of it
			_, win = create_floating_window({}, true)
			vim.api.nvim_win_set_buf(win, state.floating_buf)
		end
	else
		-- Otherwise create a new buffer
		buf, win = create_floating_window({}, true)
		state.floating_buf = buf
	end

	-- Create new terminal channel
	local chan = vim.api.nvim_open_term(state.floating_buf, {})
	if not chan or chan <= 0 then
		vim.notify("Failed to create terminal channel", vim.log.levels.ERROR)
		return
	end
	state.floating_chan = chan

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
			if not vim.api.nvim_buf_is_valid(state.floating_buf) then
				return
			end
			local output = table.concat(data, "\n")
			vim.api.nvim_chan_send(chan, output)
		end,
		on_exit = function(_, _)
			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(state.floating_buf) then
					vim.bo[state.floating_buf].modifiable = false
					if vim.api.nvim_get_current_buf() == state.floating_buf then
						vim.cmd("stopinsert")
					end
				end
			end)
		end,
	})

	-- Set keymaps only if they haven't been set for this buffer
	if not vim.b[state.floating_buf].jj_keymaps_set then
		vim.keymap.set(
			{ "n", "v" },
			"i",
			function() end,
			{ buffer = state.floating_buf, noremap = true, silent = true }
		)
		vim.keymap.set(
			{ "n", "v" },
			"c",
			function() end,
			{ buffer = state.floating_buf, noremap = true, silent = true }
		)
		vim.keymap.set(
			{ "n", "v" },
			"a",
			function() end,
			{ buffer = state.floating_buf, noremap = true, silent = true }
		)
		vim.keymap.set(
			{ "n", "v" },
			"q",
			close_floating_buffer,
			{ buffer = state.floating_bufbuf, noremap = true, silent = true, desc = "Close the floating buffer" }
		)
		vim.keymap.set(
			{ "n" },
			"<ESC>",
			hide_floating_window,
			{ buffer = state.floating_bufbuf, noremap = true, silent = true, desc = "Hide the buffer" }
		)
		vim.b[state.floating_buf].jj_keymaps_set = true
	end

	-- Set up cleanup autocmd only once per buffer
	if not vim.b[state.floating_buf].jj_cleanup_set then
		vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
			buffer = state.floating_buf,
			callback = function()
				if state.floating_buf and vim.api.nvim_buf_is_valid(state.floating_buf) then
					state.floating_buf = nil
				end
				if state.floating_chan then
					vim.fn.chanclose(chan)
				end
				if jid then
					vim.fn.jobstop(jid)
				end
			end,
		})
		vim.b[state.floating_buf].jj_cleanup_set = true
	end
end

--- Handle diffing a log line
local function handle_log_diff()
	local line = vim.api.nvim_get_current_line()

	local revset = get_rev_from_log_line(line)

	if revset then
		local cmd = string.format("jj diff -r %s", revset)
		run_floating(cmd)
	else
		utils.notify("No valid revision found in the log line", vim.log.levels.ERROR)
	end
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
		vim.keymap.set(
			{ "n", "v" },
			"q",
			close_terminal_buffer,
			{ buffer = state.buf, noremap = true, silent = true, desc = "Close the terminal buffer" }
		)
		vim.keymap.set(
			{ "n" },
			"<ESC>",
			close_terminal_buffer,
			{ buffer = state.buf, noremap = true, silent = true, desc = "Close the terminal buffer" }
		)

		-- Add Enter key mapping for status buffers to open files
		local cmd_parts = vim.split(cmd, " ")
		if cmd_parts[2] == "st" or cmd_parts[2] == "status" then
			vim.keymap.set(
				{ "n" },
				"<CR>",
				handle_status_enter,
				{ buffer = state.buf, noremap = true, silent = true, desc = "Open file under cursor" }
			)
			vim.keymap.set(
				{ "n" },
				"X",
				handle_status_restore,
				{ buffer = state.buf, noremap = true, silent = true, desc = "Restore file under cursor" }
			)
		elseif cmd_parts[2] == "log" then
			vim.keymap.set(
				{ "n" },
				"<CR>",
				handle_log_enter,
				{ buffer = state.buf, noremap = true, silent = true, desc = "Edit change under cursor" }
			)
			vim.keymap.set(
				{ "n" },
				"d",
				handle_log_diff,
				{ buffer = state.buf, noremap = true, silent = true, desc = "Diff change under cursor" }
			)
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

---@class jj.cmd.diff_opts
---@field current boolean Wether or not to only diff the current buffer

--- Jujutsu diff
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

	run(cmd)
end

--- Jujutsu rebase
function M.rebase()
	if not utils.ensure_jj() then
		return
	end

	-- show log before rebasing
	M.log({})
	vim.ui.input({
		prompt = "Rebase destination: ",
		default = "trunk()",
	}, function(input)
		if input then
			local cmd = string.format("jj rebase -d '%s'", input)
			utils.notify(string.format("Beginning rebase on %s", input), vim.log.levels.INFO)
			local _, success = utils.execute_command(cmd, "Error rebasing")
			if success then
				utils.notify("Rebase successful.", vim.log.levels.INFO)
				M.log({})
			end
		else
			close_terminal_buffer()
		end
	end)
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
	elseif subcommand == "rebase" then
		M.rebase()
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
