--- @class jj.ui.terminal
local M = {}

--- Terminal configuration
--- @class jj.ui.terminal.opts
--- @field cursor_render_delay integer The delay in ms when cursor rerendering the terminal state (default: 10ms). If you're loosing the column of the cursor try adding more delay. I currently did not find a better way to do so due to async handling of the ouptut in the terminal

local buffer = require("jj.core.buffer")

--- @type jj.ui.terminal.opts
local opts = {
	cursor_render_delay = 10,
}

--- @class jj.ui.terminal.state
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

	-- Cursor position
	cursor_restore_pos = nil,
}

-- Re-export
M.state = state

--- Setup function to configure terminal options
--- @param user_opts jj.ui.terminal.opts Configuration options
function M.setup(user_opts)
	opts = vim.tbl_deep_extend("force", opts, user_opts or {})
end

--- Help for terminal buffer
function M.keymap_help()
	-- get the normal mode keys defined for the current buffer
	local keys = vim.api.nvim_buf_get_keymap(0, "n")

	-- sort the keys table by desc
	table.sort(keys, function(a, b)
		return (a.desc or "") < (b.desc or "")
	end)

	-- Figure out the width of the longest key for later formatting
	-- Ignore keys for entries without a desc
	local max_key_width = 0
	for _, mapping in ipairs(keys) do
		local desc = mapping["desc"]
		if desc ~= nil then
			local key = mapping["lhs"]
			local key_width = vim.api.nvim_strwidth(key)
			if key_width > max_key_width then
				max_key_width = key_width
			end
		end
	end

	-- create a buffer and floating window to show the key mappings
	local buf, win = buffer.create_float({
		title = " Key mappings ",
		title_pos = "left",
		enter = true,
		bufhidden = "hide",
		win_options = {
			wrap = true,
			number = false,
			relativenumber = false,
			cursorline = false,
			signcolumn = "no",
		},
	})

	-- helper function to pad a given key with spaces if necessary such that
	-- its size will match max_key_width calculated above.
	local function space_pad(key)
		local key_width = vim.api.nvim_strwidth(key)
		local delta = max_key_width - key_width
		if delta > 0 then
			return key .. string.rep(" ", delta)
		end
		return key
	end

	-- create formated entries for items with a non-nil desc
	local lines = {}
	for _, entry in ipairs(keys) do
		if entry["desc"] ~= nil then
			local line = string.format("  %s   %s", space_pad(entry["lhs"]), entry["desc"])
			table.insert(lines, line)
		end
	end

	-- add some helper text at the end
	table.insert(lines, "")
	table.insert(lines, '   Use "q" or ESC to close this window')

	-- add the formatted lines to the buffer
	vim.api.nvim_buf_set_lines(buf, 3, -1, false, lines)

	-- Use q or ESC to close the buffer
	vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf })
	vim.keymap.set("n", "<Esc>", "<cmd>close<CR>", { buffer = buf })
end

--- Close the current terminal buffer if it exists
function M.close_terminal_buffer()
	buffer.close(state.buf)
end

--- Close the current terminal buffer if it exists
function M.close_floating_buffer()
	buffer.close(state.floating_buf)
end

--- Hide the current floating window
function M.hide_floating_buffer()
	if not state.floating_buf then
		return
	elseif state.floating_buf and vim.api.nvim_buf_is_valid(state.floating_buf) then
		vim.cmd("hide")
	end
end

--- Store the current cursor position, the terminal will restore it on the next render
function M.store_cursor_position()
	if state.buf then
		state.cursor_restore_pos = buffer.get_cursor(state.buf)
	end
end

--- Restore the stored cursor position
function M.restore_cursor_position()
	if not state.cursor_restore_pos or not state.buf then
		return
	end

	buffer.set_cursor(
		state.buf,
		state.cursor_restore_pos,
		{ delay = opts.cursor_render_delay and opts.cursor_render_delay or 10 }
	)
	state.cursor_restore_pos = nil
end

--- Run the command in a floating window
--- @param cmd string The command to run in the floating window
--- @param keymaps jj.core.buffer.keymap[]|nil Additional keymaps to set for this floating buffer
function M.run_floating(cmd, keymaps)
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
	local buf, win = buffer.create_float({
		title = " JJ Diff ",
		title_pos = "center",
		enter = true,
		bufhidden = "hide",
		win_options = {
			wrap = true,
			number = false,
			relativenumber = false,
			cursorline = false,
			signcolumn = "no",
		},
		on_exit = function(b)
			if state.floating_buf == b then
				state.floating_buf = nil
			end
			if state.floating_chan then
				vim.fn.chanclose(state.floating_chan)
				state.floating_chan = nil
			end
			if state.floating_job_id then
				vim.fn.jobstop(state.floating_job_id)
				state.floating_job_id = nil
			end
		end,
	})
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
			if not state.floating_buf or not vim.api.nvim_buf_is_valid(state.floating_buf) then
				return
			end
			local output = table.concat(data, "\n")
			vim.api.nvim_chan_send(chan, output)
		end,
		on_exit = function(_, _) --[[ exit_code ]]
			vim.schedule(function()
				if state.floating_buf and vim.api.nvim_buf_is_valid(state.floating_buf) then
					buffer.set_modifiable(state.floating_buf, false)
					buffer.stop_insert(state.floating_buf)
				end
			end)
		end,
	})

	if jid <= 0 then
		vim.api.nvim_chan_send(chan, "Failed to start command: " .. cmd .. "\r\n")
		state.floating_chan = nil
	else
		state.floating_job_id = jid
	end

	-- Set keymaps only if they haven't been set for this buffer
	if not vim.b[state.floating_buf].jj_keymaps_set then
		local default_keymaps = {
			{ modes = { "n", "v" }, lhs = "i", rhs = function() end },
			{ modes = { "n", "v" }, lhs = "c", rhs = function() end },
			{ modes = { "n", "v" }, lhs = "a", rhs = function() end },
			{ modes = { "n", "v" }, lhs = "u", rhs = function() end },
		}

		-- Merge default keymaps with provided keymaps
		if keymaps and #keymaps > 0 then
			for _, km in ipairs(keymaps) do
				table.insert(default_keymaps, km)
			end
		end

		-- Remove prompt keymaps
		buffer.remove_keymaps(state.floating_buf, {
			{ modes = { "n", "v" }, lhs = "[[", rhs = function() end },
			{ modes = { "n", "v" }, lhs = "]]", rhs = function() end },
		})

		buffer.set_keymaps(state.floating_buf, default_keymaps)
		vim.b[state.floating_buf].jj_keymaps_set = true
	end
end

--- Run a command and show it's output in a terminal buffer
--- If a previous command already existed it smartly reuses the buffer cleaning the previous output
--- @param cmd string|string[] The command to run in the terminal buffer
--- @param keymaps jj.core.buffer.keymap[]|nil Additional keymaps to set for this command buffer
--- @return integer|nil buf The buffer handle, or nil on failure
function M.run(cmd, keymaps)
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
	state.buf = buffer.create({
		split = "horizontal",
		size = math.floor(vim.o.lines / 2),
		on_exit = function(buf)
			if state.buf == buf then
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

	local win = vim.api.nvim_get_current_win()
	vim.bo[state.buf].bufhidden = "wipe"

	-- Create new terminal channel
	local chan = vim.api.nvim_open_term(state.buf, {})
	if not chan or chan <= 0 then
		vim.notify("Failed to create terminal channel", vim.log.levels.ERROR)
		return
	end
	state.chan = chan

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
			if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) or not state.chan then
				return
			end
			local output = table.concat(data, "\n")
			vim.api.nvim_chan_send(state.chan, output)
		end,
		on_exit = function(_, exit_code)
			vim.schedule(function()
				-- Check buffer still exists (it might have been closed)
				if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
					return
				end
				-- Store the subcommand on successful exit
				if exit_code == 0 then
					state.buf_cmd = cmd[2] or nil
				end
				-- Make the buffer not modifiable
				buffer.set_modifiable(state.buf, false)
				buffer.stop_insert(state.buf)
				-- Restore cursor position after buffer is ready
				if state.cursor_restore_pos then
					M.restore_cursor_position()
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
		buffer.set_keymaps(state.buf, {
			{ modes = { "n" }, lhs = "g?", rhs = M.keymap_help },
			-- Disable insert, command and append modes
			{ modes = { "n", "v" }, lhs = "i", rhs = function() end },
			{ modes = { "n", "v" }, lhs = "c", rhs = function() end },
			{ modes = { "n", "v" }, lhs = "a", rhs = function() end },
			{ modes = { "n", "v" }, lhs = "u", rhs = function() end },
		})

		vim.b[state.buf].jj_keymaps_set = true
	end

	-- Remove prompt keymaps
	buffer.remove_keymaps(state.buf, {
		{ modes = { "n", "v" }, lhs = "[[", rhs = function() end },
		{ modes = { "n", "v" }, lhs = "]]", rhs = function() end },
	})

	-- Remove command-specific keymaps from previous runs
	if vim.b[state.buf].jj_command_keymaps then
		buffer.remove_keymaps(state.buf, vim.b[state.buf].jj_command_keymaps)
		vim.b[state.buf].jj_command_keymaps = nil
	end

	-- Add command-specific keymaps for jj buffers
	local new_command_keymaps = {}

	-- Append the given keymaps
	-- Add a debug
	if keymaps and #keymaps > 0 then
		for _, km in ipairs(keymaps) do
			table.insert(new_command_keymaps, km)
		end
	end

	-- Status keymaps are already handled in cmd.lua via status_keymaps()
	-- No need to duplicate them here
	if #new_command_keymaps > 0 then
		buffer.set_keymaps(state.buf, new_command_keymaps)
		vim.b[state.buf].jj_command_keymaps = new_command_keymaps
	end

	vim.cmd("stopinsert")

	return state.buf
end

--- Replace keymaps for normal terminal
--- @param keymaps jj.core.buffer.keymap[] New keymaps to set
function M.replace_terminal_keymaps(keymaps)
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end

	-- Remove previous keymaps if any
	if vim.b[state.buf].jj_command_keymaps then
		buffer.remove_keymaps(state.buf, vim.b[state.buf].jj_command_keymaps)
		vim.b[state.buf].jj_command_keymaps = nil
	end

	-- Set new keymaps
	if keymaps and #keymaps > 0 then
		buffer.set_keymaps(state.buf, keymaps)
		vim.b[state.buf].jj_command_keymaps = keymaps
	end
end

--- @class jj.ui.terminal.tooltip_opts
--- @field title? string Tooltip title
--- @field enter? boolean Whether to enter the tooltip window (default: false)
--- @field keymaps? jj.core.buffer.keymap[] Keymaps to set on the tooltip buffer
--- @field on_exit? fun(buf: number) Callback when tooltip is closed
--- @field width? number Tooltip width (default: 80% of columns)
--- @field height? number Tooltip height (default: 80% of lines)

--- Run a command in a PTY-based tooltip window
--- Unlike run_floating, this doesn't track state - caller manages the buffer reference
--- @param cmd string The command to run
--- @param opts? jj.ui.terminal.tooltip_opts Tooltip options
--- @return number|nil buf Buffer handle, or nil on failure
--- @return number|nil win Window handle, or nil on failure
function M.run_tooltip(cmd, opts)
	opts = opts or {}

	local buf, win = buffer.create_float({
		title = opts.title or " JJ ",
		title_pos = "center",
		enter = opts.enter or false,
		bufhidden = "wipe",
		relative = "cursor",
		row = 1,
		col = 0,
		width = opts.width,
		height = opts.height,
		win_options = {
			wrap = true,
			number = false,
			relativenumber = false,
			cursorline = false,
			signcolumn = "no",
		},
	})

	local chan = vim.api.nvim_open_term(buf, {})
	if not chan or chan <= 0 then
		vim.notify("Failed to create terminal channel", vim.log.levels.ERROR)
		vim.api.nvim_buf_delete(buf, { force = true })
		return nil, nil
	end

	local job_id = nil

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
			if not buf or not vim.api.nvim_buf_is_valid(buf) then
				return
			end
			local output = table.concat(data, "\n")
			vim.api.nvim_chan_send(chan, output)
		end,
		on_exit = function()
			vim.schedule(function()
				if buf and vim.api.nvim_buf_is_valid(buf) then
					buffer.set_modifiable(buf, false)
					buffer.stop_insert(buf)
				end
			end)
		end,
	})

	if jid <= 0 then
		vim.api.nvim_chan_send(chan, "Failed to start command: " .. cmd .. "\r\n")
		return buf, win
	end

	job_id = jid

	vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
		buffer = buf,
		once = true,
		callback = function()
			if chan then
				pcall(vim.fn.chanclose, chan)
			end
			if job_id then
				pcall(vim.fn.jobstop, job_id)
			end
			if opts.on_exit then
				opts.on_exit(buf)
			end
		end,
	})

	vim.keymap.set("n", "<Esc>", function()
		buffer.close(buf, true)
	end, { buffer = buf, silent = true })

	-- Close when cursor moves in other windows (unless suppress flag is set)
	vim.api.nvim_create_autocmd("CursorMoved", {
		callback = function()
			if
				vim.api.nvim_buf_is_valid(buf)
				and vim.api.nvim_win_is_valid(win)
				and vim.api.nvim_get_current_win() ~= win
			then
				-- Don't close if suppress flag is set (e.g., when opening floating diff from tooltip)
				if vim.b[buf].jj_suppress_auto_close then
					return
				end
				buffer.close(buf, true)
				return true
			end
		end,
	})

	if opts.keymaps and #opts.keymaps > 0 then
		buffer.set_keymaps(buf, opts.keymaps)
	end

	vim.cmd("stopinsert")

	return buf, win
end

--- Replace keymaps for floating terminal
--- @param keymaps jj.core.buffer.keymap[] New keymaps to set
function M.replace_floating_keymaps(keymaps)
	if not state.floating_buf or not vim.api.nvim_buf_is_valid(state.floating_buf) then
		return
	end
	-- Remove previous keymaps if any
	if vim.b[state.floating_buf].jj_command_keymaps then
		buffer.remove_keymaps(state.floating_buf, vim.b[state.floating_buf].jj_command_keymaps)
		vim.b[state.floating_buf].jj_command_keymaps = nil
	end
	-- Set new keymaps
	if keymaps and #keymaps > 0 then
		buffer.set_keymaps(state.floating_buf, keymaps)
		vim.b[state.floating_buf].jj_command_keymaps = keymaps
	end
end

--- @class jj.ui.terminal.scratch_opts
--- @field title? string Buffer name/title
--- @field size? number Split size in columns (default: 80)
--- @field direction? "left"|"right" Split direction (default: "right")
--- @field enter? boolean Whether to enter the new window (default: true)
--- @field keymaps? jj.core.buffer.keymap[] Keymaps to set on the buffer
--- @field on_exit? fun(buf: number) Callback when buffer is closed

--- Run a command in a PTY-based in a scratch vertical split
--- Unlike run_floating, this creates a split next to the current window
--- @param cmd string The command to run
--- @param scratch_opts? jj.ui.terminal.scratch_opts Ephemeral split options
--- @return number|nil buf Buffer handle, or nil on failure
--- @return number|nil win Window handle, or nil on failure
function M.run_scratch(cmd, scratch_opts)
	scratch_opts = scratch_opts or {}

	local size = scratch_opts.size or 80
	local direction = scratch_opts.direction or "right"
	local enter = scratch_opts.enter ~= false

	local buf, win = buffer.create({
		split = "vertical",
		direction = direction,
		size = size,
		bufhidden = "wipe",
		win_options = {
			wrap = true,
			number = false,
			relativenumber = false,
			cursorline = false,
			signcolumn = "no",
		},
	})

	-- Focus the new window if enter is true
	if enter and win then
		vim.api.nvim_set_current_win(win)
	end

	if scratch_opts.title then
		pcall(vim.api.nvim_buf_set_name, buf, scratch_opts.title)
	end

	local chan = vim.api.nvim_open_term(buf, {})
	if not chan or chan <= 0 then
		vim.notify("Failed to create terminal channel", vim.log.levels.ERROR)
		vim.api.nvim_buf_delete(buf, { force = true })
		return nil, nil
	end

	local job_id = nil

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
			if not buf or not vim.api.nvim_buf_is_valid(buf) then
				return
			end
			local output = table.concat(data, "\n")
			vim.api.nvim_chan_send(chan, output)
		end,
		on_exit = function()
			vim.schedule(function()
				if buf and vim.api.nvim_buf_is_valid(buf) then
					buffer.set_modifiable(buf, false)
					buffer.stop_insert(buf)
				end
			end)
		end,
	})

	if jid <= 0 then
		vim.api.nvim_chan_send(chan, "Failed to start command: " .. cmd .. "\r\n")
		return buf, win
	end

	job_id = jid

	vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
		buffer = buf,
		once = true,
		callback = function()
			if chan then
				pcall(vim.fn.chanclose, chan)
			end
			if job_id then
				pcall(vim.fn.jobstop, job_id)
			end
			if scratch_opts.on_exit then
				scratch_opts.on_exit(buf)
			end
		end,
	})

	-- Close with q or Esc
	vim.keymap.set("n", "q", function()
		buffer.close(buf, true)
	end, { buffer = buf, silent = true })

	vim.keymap.set("n", "<Esc>", function()
		buffer.close(buf, true)
	end, { buffer = buf, silent = true })

	-- Disable insert/command/append modes
	buffer.set_keymaps(buf, {
		{ modes = { "n", "v" }, lhs = "i", rhs = function() end },
		{ modes = { "n", "v" }, lhs = "c", rhs = function() end },
		{ modes = { "n", "v" }, lhs = "a", rhs = function() end },
	})

	if scratch_opts.keymaps and #scratch_opts.keymaps > 0 then
		buffer.set_keymaps(buf, scratch_opts.keymaps)
	end

	vim.cmd("stopinsert")

	return buf, win
end

return M
