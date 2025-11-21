--- @class jj.ui.terminal
local M = {}

local utils = require("jj.utils")
local parser = require("jj.core.parser")

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

M.state = state

--- Close the current terminal buffer if it exists
function M.close_terminal_buffer()
	if not state.buf then
		return
	elseif state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		vim.cmd("bwipeout! " .. state.buf)
	else
		vim.cmd("close")
	end
end

--- Close the current terminal buffer if it exists
local function close_floating_buffer()
	if not state.floating_buf then
		return
	elseif state.floating_buf and vim.api.nvim_buf_is_valid(state.floating_buf) then
		vim.cmd("bwipeout! " .. state.floating_buf)
	else
		vim.cmd("close")
	end
end

--- Hide the current floating window
local function hide_floating_window()
	if not state.floating_buf then
		return
	elseif state.floating_buf and vim.api.nvim_buf_is_valid(state.floating_buf) then
		vim.cmd("hide")
	end
end

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

local function handle_status_restore()
	local file_info = parser.parse_file_info_from_status_line(vim.api.nvim_get_current_line())
	if not file_info then
		return
	end

	local runner = require("jj.core.runner")

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

	local runner = require("jj.core.runner")
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
	M.close_terminal_buffer()
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
	local revset = parser.get_rev_from_log_line(line)
	if not revset or revset == "" then
		return
	end

	local runner = require("jj.core.runner")

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
		M.run_floating(cmd)
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
function M.run_floating(cmd)
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

	-- Wipe old buffer if it exists
	if state.floating_buf and vim.api.nvim_buf_is_valid(state.floating_buf) then
		vim.api.nvim_buf_delete(state.floating_buf, { force = true })
		state.floating_buf = nil
	end

	-- Create new floating buffer
	local buf, win = create_floating_window({}, true)
	state.floating_buf = buf

	-- Create new terminal channel
	local chan = vim.api.nvim_open_term(state.floating_buf, {})
	if not chan or chan <= 0 then
		vim.notify("Failed to create terminal channel", vim.log.levels.ERROR)
		return
	end
	state.floating_chan = chan

	-- Move cursor to top before output arrives
	vim.api.nvim_win_set_cursor(win, { 1, 0 })

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
		on_exit = function(_, _) --[[ exit_code ]]
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
			{ buffer = state.floating_buf, noremap = true, silent = true, desc = "Close the floating buffer" }
		)
		vim.keymap.set(
			{ "n" },
			"<ESC>",
			hide_floating_window,
			{ buffer = state.floating_buf, noremap = true, silent = true, desc = "Hide the buffer" }
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

--- Run a command and show it's output in a terminal buffer
--- If a previous command already existed it smartly reuses the buffer cleaning the previous output
--- @param cmd string|string[]
function M.run(cmd)
	if type(cmd) == "string" then
		cmd = { cmd }
	end

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

	-- Wipe old buffer if it exists
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		vim.api.nvim_buf_delete(state.buf, { force = true })
		state.buf = nil
	end

	-- Create new terminal buffer
	local height = math.floor(vim.o.lines / 2)
	vim.cmd(string.format("%dsplit", height))

	local win = vim.api.nvim_get_current_win()
	state.buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(win, state.buf)
	vim.bo[state.buf].bufhidden = "wipe"

	-- Create new terminal channel
	local chan = vim.api.nvim_open_term(state.buf, {})
	if not chan or chan <= 0 then
		vim.notify("Failed to create terminal channel", vim.log.levels.ERROR)
		return
	end
	state.chan = chan

	-- Move cursor to top before output arrives
	vim.api.nvim_win_set_cursor(win, { 1, 0 })

	-- If the command is a string split it into parts
	-- to store the subcommand later
	if #cmd == 1 then
		cmd = vim.split(cmd[1], "%s+")
	end

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
					state.buf_cmd = cmd[2] or nil
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
			M.close_terminal_buffer,
			{ buffer = state.buf, noremap = true, silent = true, desc = "Close the terminal buffer" }
		)
		vim.keymap.set(
			{ "n" },
			"<ESC>",
			M.close_terminal_buffer,
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
	if cmd[2] == "st" or cmd[2] == "status" then
		register_command_keymap({ "n" }, "<CR>", handle_status_enter, { desc = "Open file under cursor" })
		register_command_keymap({ "n" }, "X", handle_status_restore, { desc = "Restore file under cursor" })
	elseif cmd[2] == "log" then
		-- Edit
		register_command_keymap({ "n" }, "<CR>", function()
			handle_log_enter(false)
		end, { desc = "Edit change under cursor" })
		register_command_keymap({ "n" }, "<S-CR>", function()
			handle_log_enter(true)
		end, { desc = "Edit change under cursor ignoring immutability" })
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
		-- Undo/Redo
		register_command_keymap({ "n" }, "u", function()
			require("jj.cmd").undo()
		end, { desc = "Undo last operation" })
		register_command_keymap({ "n" }, "r", function()
			require("jj.cmd").redo()
		end, { desc = "Redo last operation" })
		register_command_keymap({ "n" }, "D", handle_log_describe, { desc = "Describe change under cursor" })
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

return M
