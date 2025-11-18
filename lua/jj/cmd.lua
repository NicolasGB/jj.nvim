--- @class jj.cmd
local M = {}

local utils = require("jj.utils")
local diff = require("jj.diff")

-- Config for cmd module
M.config = {
	describe_editor = "buffer", -- "buffer" or "input"
}

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

	-- The current command being displayed
	--- @type string|nil
	buf_cmd = nil,

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

local function handle_status_enter()
	local file_info = utils.parse_file_info_from_status_line()

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
	local file_info = utils.parse_file_info_from_status_line()

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
		diamond = "\226\151\134", -- ◆ U+25C6
		circle = "\226\151\139", -- ○ U+25CB
		conflict = "\195\151", -- × U+00D7
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
	local revset = get_rev_from_log_line(line)
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
	local _, success = utils.execute_command(cmd, string.format(cfg.err, revset))
	if not success then
		return
	end

	utils.notify(string.format(cfg.ok, revset), vim.log.levels.INFO)
	-- Refresh the log buffer after creating the change.
	M.log()
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
			DFT_BACKGROUND = "light",
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
		local cmd = string.format("jj show %s", revset)
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
		state.buf_cmd = nil
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

	-- Split the current command in parts for further use
	local cmd_parts = vim.split(cmd, "%s+")

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
			DFT_BACKGROUND = "light",
		},
		on_stdout = function(_, data)
			if not vim.api.nvim_buf_is_valid(state.buf) or not state.chan then
				return
			end
			local output = table.concat(data, "\n")
			vim.api.nvim_chan_send(state.chan, output)
		end,
		on_exit = function(_, exit_code)
			vim.schedule(function()
				-- Make the buffer not modifiable
				if vim.api.nvim_buf_is_valid(state.buf) then
					vim.bo[state.buf].modifiable = false
					if vim.api.nvim_get_current_buf() == state.buf then
						vim.cmd("stopinsert")
					end
				end
				-- Store the subcommand on successful exit
				if exit_code == 0 then
					state.buf_cmd = cmd_parts[2] or nil
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
	-- Set base keymaps only if they haven't been set for this buffer yet
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

		vim.b[state.buf].jj_keymaps_set = true
	end

	-- Remove command-specific keymaps from previous runs
	if vim.b[state.buf].jj_command_keymaps then
		for _, map in ipairs(vim.b[state.buf].jj_command_keymaps) do
			local modes = map.modes
			if type(modes) ~= "table" then
				modes = { modes }
			end
			for _, mode in ipairs(modes) do
				pcall(vim.keymap.del, mode, map.lhs, { buffer = state.buf })
			end
		end
		vim.b[state.buf].jj_command_keymaps = nil
	end

	-- Add command-specific keymaps for jj buffers
	local new_command_keymaps = {}
	local function register_command_keymap(modes, lhs, rhs, opts)
		local normalized_modes = type(modes) == "table" and vim.deepcopy(modes) or { modes }
		opts = opts or {}
		opts.buffer = state.buf
		if opts.noremap == nil then
			opts.noremap = true
		end
		if opts.silent == nil then
			opts.silent = true
		end
		vim.keymap.set(modes, lhs, rhs, opts)
		table.insert(new_command_keymaps, { modes = normalized_modes, lhs = lhs })
	end

	-- Add Enter key mapping for status buffers to open files
	if cmd_parts[2] == "st" or cmd_parts[2] == "status" then
		register_command_keymap({ "n" }, "<CR>", handle_status_enter, { desc = "Open file under cursor" })
		register_command_keymap({ "n" }, "X", handle_status_restore, { desc = "Restore file under cursor" })
	elseif cmd_parts[2] == "log" then
		-- Edit
		register_command_keymap({ "n" }, "<CR>", handle_log_enter, { desc = "Edit change under cursor" })
		-- Diff
		register_command_keymap({ "n" }, "d", handle_log_diff, { desc = "Diff change under cursor" })
		-- New
		register_command_keymap({ "n" }, "n", handle_log_new, { desc = "New change off the change under cursor" })
		register_command_keymap({ "n" }, "<C-n>", function()
			handle_log_new("after")
		end, { desc = "New change after the change under cursor" })
		register_command_keymap({ "n" }, "<S-n>", function()
			handle_log_new("after", true)
		end, { desc = "New change after the change under cursor ignoring immutability" })
	end

	if #new_command_keymaps > 0 then
		vim.b[state.buf].jj_command_keymaps = new_command_keymaps
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
				state.buf_cmd = nil
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

	-- Use --stdin to properly handle multi-line and special characters
	local _, success = utils.execute_command("jj describe --stdin", "Failed to describe", description)
	if success then
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
	if description then
		-- Description provided directly
		execute_describe(description)
	else
		-- Use buffer editor mode
		if M.config.describe_editor == "buffer" then
			-- Build initial lines
			local status_files = utils.get_status_files()
			local text = { "JJ: This commit contains the following changes:" }
			for _, item in ipairs(status_files) do
				table.insert(text, string.format("JJ:     %s %s", item.status, item.file))
			end
			table.insert(text, "JJ:") -- blank line
			table.insert(text, 'JJ: Lines starting with "JJ:" (like this one) will be ignored when finalizing')
			table.insert(text, "") -- Empty line to separate from user input
			table.insert(text, "") -- Another empty line where user can start typing

			utils.open_ephemeral_buffer(text, function(buf_lines)
				local user_lines = {}
				for _, line in ipairs(buf_lines) do
					if not line:match("^JJ:") then
						table.insert(user_lines, line)
					end
				end
				-- Join lines and trim leading/trailing whitespace
				local trimmed_description = table.concat(user_lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
				execute_describe(trimmed_description)
			end)
		else
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
end

--- Jujutsu status.
--
--  it executes `jj st` and either:
--   1. Shows the output in a notification (if `opts.notify` is true), or
--   2. Displays it in the buffer by default.
--
-- @param opts? table Optional settings:
-- @field notify boolean If true, show the status in a notification instead of buffer.
function M.status(opts)
	if not utils.ensure_jj() then
		return
	end

	local cmd = "jj st"

	if opts and opts.notify then
		local output = utils.execute_command(cmd, "Failed to get status")
		if output then
			utils.notify(output, vim.log.levels.INFO)
		end
	else
		-- Default behavior: show in buffer
		run(cmd)
	end
end

--- @class jj.cmd.new_opts
--- @field show_log? boolean Whether or not to display the log command after creating a new
--- @field with_input? boolean Whether or not to use nvim input to decide the parent of the new commit
--- @field args? string The arguments to append to the new command

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
		-- If the show log is enabled show log
		if opts and opts.show_log then
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
		if state.buf_cmd == "log" then
			M.log()
		end
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

--- Jujutsu create bookmark
function M.bookmark_create()
	if not utils.ensure_jj() then
		return
	end

	-- show log before rebasing
	M.log({})
	vim.ui.input({
		prompt = "Bookmark name: ",
	}, function(input)
		if input then
			local cmd = string.format("jj b c %s", input)
			local _, success = utils.execute_command(cmd, "Error creating bookmark")
			if success then
				utils.notify(string.format("Bookmark `%s` created successfully for @", input), vim.log.levels.INFO)
				M.log({})
			end
		else
			close_terminal_buffer()
		end
	end)
end

--- Jujutsu delete bookmark
function M.bookmark_delete()
	if not utils.ensure_jj() then
		return
	end

	-- show log before rebasing
	M.log({})
	vim.ui.input({
		prompt = "Bookmark name: ",
	}, function(input)
		if input then
			local cmd = string.format("jj b d %s", input)
			local _, success = utils.execute_command(cmd, "Error deleting bookmark")
			if success then
				utils.notify(string.format("Bookmark `%s` deleted successfully.", input), vim.log.levels.INFO)
				M.log({})
			end
		else
			close_terminal_buffer()
		end
	end)
end

--- Jujutsu undo
function M.undo()
	if not utils.ensure_jj() then
		return
	end

	local cmd = "jj undo"
	local _, success = utils.execute_command(cmd, "Failed to undo")
	if success then
		utils.notify("Command `undo` was succesful.", vim.log.levels.INFO)
		if state.buf_cmd == "log" then
			M.log({})
		end
	end
end
---
--- Jujutsu redo
function M.redo()
	if not utils.ensure_jj() then
		return
	end

	local cmd = "jj redo"
	local _, success = utils.execute_command(cmd, "Failed to redo")
	if success then
		utils.notify("Command `redo` was succesful.", vim.log.levels.INFO)
		if state.buf_cmd == "log" then
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
		-- Use the user's default command and do not try to parse anything else
		local default_cmd, success =
			utils.execute_command("jj config get ui.default-command", "Error getting user's default command", nil, true)
		-- If we can't find the default cmd we simply run it
		if not success or default_cmd == "" then
			run("jj")
			return
		end
		-- Trim leading and trailing whitespace
		if default_cmd then
			default_cmd = default_cmd:gsub("^%s+", ""):gsub("%s+$", "")
		end
		-- Modify the args table to contain the new default command this will allow for descendant logic to parse the cmd and use builtin functions
		args = { default_cmd }
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
	if subcommand == "describe" or subcommand == "desc" then
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

--- Register the J and Jdiff commands
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

	-- Unified creation of jj diff commands with optional revision argument
	local function create_diff_command(name, fn, desc)
		vim.api.nvim_create_user_command(name, function(opts)
			local rev = opts.fargs[1]
			if rev then
				fn({ rev = rev })
			else
				fn()
			end
		end, {
			nargs = "?",
			desc = desc .. " (optionally pass jj revision)",
		})
	end

	-- Commands:
	-- Jdiff  : vertical diff by default
	-- Jhdiff : horizontal diff
	-- Jvdiff : vertical diff (explicit)
	create_diff_command("Jdiff", diff.open_vdiff, "Vertical diff against jj revision")
	create_diff_command("Jhdiff", diff.open_hdiff, "Horizontal diff against jj revision")
	create_diff_command("Jvdiff", diff.open_vdiff, "Vertical diff against jj revision")
end

return M

