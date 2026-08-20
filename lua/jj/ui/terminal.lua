--- @class jj.ui.terminal
local M = {}

--- Terminal configuration
--- @class jj.ui.terminal.opts
--- @field cursor_render_delay? integer The delay in ms when cursor rerendering the terminal state (default: 10ms). If you're loosing the column of the cursor try adding more delay. I currently did not find a better way to do so due to async handling of the ouptut in the terminal
--- @field window? jj.terminal.window Options for the window used
---
--- @class jj.terminal.window
--- @field type? "hsplit"|"vsplit"|"floating"|"tab" Type of window the terminal is displayed in
--- @field split_size? number Size % of the split window, either height (hsplit) or width (vsplit) (between 0.1 and 1.0)
--- @field floating_width? number Width % of the floating window (between 0.1 and 1.0)
--- @field floating_height? number Height % of the floating window (between 0.1 and 1.0)

local utils = require("jj.utils")
local buffer = require("jj.core.buffer")

--- @type jj.ui.terminal.opts
local opts = {}

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
	-- The current floating command being displayed
	--- @type string|nil
	floating_buf_cmd = nil,

	-- Cursor position
	cursor_restore_pos = nil,

	-- The current tooltip buffer
	--- @type integer|nil
	tooltip_buf = nil,
	-- The tooltip window
	--- @type integer|nil
	tooltip_win = nil,
	-- The tooltip channel to communicate with the terminal
	--- @type integer|nil
	tooltip_chan = nil,
	-- The tooltip_job_id
	--- @type integer|nil
	tooltip_job_id = nil,
	-- The tooltip autocmd that auto closes it
	--- @type integer|nil
	tooltip_close_autocmd = nil,
}

--- Clamps a ratio value between 0.1 and 1.0, returning a default of 1.0 if the input is invalid.
---@param value? number
---@param field string
---@return number
local function clamp_ratio(value, field)
	if type(value) ~= "number" or value < 0.1 or value > 1.0 then
		utils.notify(
			string.format("Value for field `%s` must be between `0.1` and `1.0`. Defaulted to `1.0`", field),
			vim.log.levels.WARN
		)
		return 1.0
	end
	return value
end

-- Re-export
M.state = state

--- Keymaps shared by split and non-interactive floating terminal output buffers.
--- Return a new table so callers can safely append command-specific keymaps.
--- @return jj.core.buffer.keymap[]
local function default_output_keymaps()
	return {
		{ modes = { "n" }, lhs = "g?", rhs = M.keymap_help },
		-- Disable insert, command, append, and undo in rendered command output.
		{ modes = { "n", "v" }, lhs = "i", rhs = "<Nop>" },
		{ modes = { "n", "v" }, lhs = "c", rhs = "<Nop>" },
		{ modes = { "n", "v" }, lhs = "a", rhs = "<Nop>" },
		{ modes = { "n", "v" }, lhs = "<S-a>", rhs = "<Nop>" },
		{ modes = { "n", "v" }, lhs = "<S-i>", rhs = "<Nop>" },
		{ modes = { "n", "v" }, lhs = "u", rhs = "<Nop>" },
	}
end

--- Remove the shell-prompt mappings automatically added by nvim_open_term().
--- Rendered output buffers do not contain interactive shell prompts, and command-specific
--- keymaps may reuse these keys afterward. Interactive terminals intentionally keep them.
--- @param buf integer
local function remove_prompt_keymaps(buf)
	buffer.remove_keymaps(buf, {
		{ modes = { "n" }, lhs = "[[", rhs = "<Nop>" },
		{ modes = { "n" }, lhs = "]]", rhs = "<Nop>" },
	})
end

--- Setup function to configure terminal options
--- @param user_opts jj.ui.terminal.opts Configuration options
function M.setup(user_opts)
	opts = vim.tbl_deep_extend("force", opts, user_opts or {})

	-- Clamp window ratios
	opts.window.split_size = clamp_ratio(opts.window.split_size, "terminal.window.split_size")
	opts.window.floating_width = clamp_ratio(opts.window.floating_width, "terminal.window.floating_width")
	opts.window.floating_height = clamp_ratio(opts.window.floating_height, "terminal.window.floating_height")
end

--- Help for terminal buffer
function M.keymap_help()
	local keys = vim.api.nvim_buf_get_keymap(0, "n")
	local mappings = {}
	local max_key_width = 0

	for _, mapping in ipairs(keys) do
		if mapping.desc and mapping.desc ~= "" then
			table.insert(mappings, mapping)
			max_key_width = math.max(max_key_width, vim.api.nvim_strwidth(mapping.lhs))
		end
	end

	-- Keep actions discoverable by sorting on their descriptions, with the key as
	-- a stable tie breaker.
	table.sort(mappings, function(a, b)
		local a_desc = a.desc:lower()
		local b_desc = b.desc:lower()
		if a_desc == b_desc then
			return a.lhs < b.lhs
		end
		return a_desc < b_desc
	end)

	local key_column_width = math.max(max_key_width, 3)
	local prefix_width = 2 + key_column_width + 3
	local max_window_width = math.max(30, vim.o.columns - 6)
	local natural_width = vim.api.nvim_strwidth("  KEY" .. string.rep(" ", key_column_width - 3) .. " │ ACTION")
	for _, mapping in ipairs(mappings) do
		natural_width = math.max(natural_width, prefix_width + vim.api.nvim_strwidth(mapping.desc))
	end
	local width = math.min(natural_width, max_window_width, 110)
	local description_width = math.max(12, width - prefix_width)

	local lines = {}
	local highlights = {}
	local function add_line(text, groups)
		table.insert(lines, text)
		local row = #lines - 1
		for _, group in ipairs(groups or {}) do
			table.insert(highlights, {
				row = row,
				start_col = group.start_col,
				end_col = group.end_col,
				hl_group = group.hl_group,
			})
		end
	end

	local heading = "  " .. string.format("%-" .. key_column_width .. "s", "KEY") .. " │ ACTION"
	add_line(heading, {
		{ start_col = 2, end_col = #heading, hl_group = "Title" },
	})
	local divider = "  " .. string.rep("─", key_column_width) .. "─┼─" .. string.rep("─", description_width)
	add_line(divider, {
		{ start_col = 0, end_col = #divider, hl_group = "FloatBorder" },
	})

	-- Wrap descriptions ourselves to keep continuation lines aligned with the
	-- action column instead of letting the window wrap from column zero.
	for _, mapping in ipairs(mappings) do
		local chunks = {}
		local current = ""
		for word in mapping.desc:gmatch("%S+") do
			local candidate = current == "" and word or (current .. " " .. word)
			if current ~= "" and vim.api.nvim_strwidth(candidate) > description_width then
				table.insert(chunks, current)
				current = word
			else
				current = candidate
			end
		end
		table.insert(chunks, current)

		for index, chunk in ipairs(chunks) do
			if index == 1 then
				local padded_key = mapping.lhs .. string.rep(" ", key_column_width - vim.api.nvim_strwidth(mapping.lhs))
				local line = "  " .. padded_key .. " │ " .. chunk
				add_line(line, {
					{ start_col = 2, end_col = 2 + #mapping.lhs, hl_group = "Special" },
					{
						start_col = 2 + key_column_width + 1,
						end_col = 2 + key_column_width + 2,
						hl_group = "FloatBorder",
					},
				})
			else
				add_line(string.rep(" ", prefix_width) .. chunk)
			end
		end
	end

	local height = math.min(#lines, math.max(3, vim.o.lines - 6))
	local buf, win = buffer.create_float({
		title = string.format(" JJ Keymaps · %d ", #mappings),
		title_pos = "center",
		enter = true,
		bufhidden = "wipe",
		width = width,
		height = height,
		win_options = {
			wrap = false,
			number = false,
			relativenumber = false,
			cursorline = true,
			signcolumn = "no",
			winfixbuf = true,
		},
	})

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	local namespace = vim.api.nvim_create_namespace("jj_keymap_help")
	for _, highlight in ipairs(highlights) do
		vim.api.nvim_buf_set_extmark(buf, namespace, highlight.row, highlight.start_col, {
			end_col = highlight.end_col,
			hl_group = highlight.hl_group,
			priority = 200,
		})
	end
	vim.bo[buf].filetype = "jj-keymaps"
	vim.bo[buf].modifiable = false
	vim.api.nvim_win_set_cursor(win, { math.min(3, #lines), 0 })
	vim.api.nvim_win_set_config(win, {
		footer = " q / Esc close ",
		footer_pos = "right",
	})

	vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf, silent = true })
	vim.keymap.set("n", "<Esc>", "<cmd>close<CR>", { buffer = buf, silent = true })
end

--- Close the current terminal buffer if it exists
function M.close_terminal_buffer()
	-- If the tooltip is showing that's what we want to close
	if state.tooltip_buf then
		M.close_tooltip()
		return
	end

	-- Otherwise close the buffer
	buffer.close(state.buf)
	state.buf_cmd = nil
	state.chan = nil
	state.job_id = nil
end

--- Close the current terminal buffer if it exists
function M.close_floating_buffer()
	buffer.close(state.floating_buf)
	state.floating_chan = nil
	state.floating_job_id = nil
	state.floating_buf = nil
	state.floating_buf_cmd = nil
end

--- Close the current tooltip buffer if it exists
function M.close_tooltip()
	if not state.tooltip_buf then
		return
	end
	buffer.close(state.tooltip_buf)
	if state.tooltip_close_autocmd then
		pcall(vim.api.nvim_del_autocmd, state.tooltip_close_autocmd)
	end
	state.tooltip_chan = nil
	state.tooltip_job_id = nil
	state.tooltip_buf = nil
	state.tooltip_win = nil
	state.tooltip_close_autocmd = nil
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

--- Check whether the log buffer is currently active
--- @return boolean
function M.is_log_buffer_open()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return false
	end
	if opts.window.type == "floating" then
		return state.floating_buf_cmd == "log"
	end
	return state.buf_cmd == "log"
end

--- Run the command in a floating window
--- @param cmd string[] The command to run in the floating window
--- @param keymaps jj.core.buffer.keymap[]|nil Additional keymaps to set for this floating buffer
--- @param float_opts? {title?: string, modifiable?: boolean, keep_modifiable?: boolean, on_exit?: fun(exit_code: integer), interactive?: boolean}
function M.run_floating(cmd, keymaps, float_opts)
	local jj_cmd = require("jj.cmd")
	keymaps = jj_cmd.merge_keymaps(keymaps or {}, jj_cmd.floating_keymaps())
	float_opts = float_opts or {}

	-- Clean up previous state if invalid
	if state.floating_buf and not vim.api.nvim_buf_is_valid(state.floating_buf) then
		state.floating_buf = nil
		state.floating_chan = nil
		state.floating_job_id = nil
		state.floating_buf_cmd = nil
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
		title = float_opts.title or " JJ Diff ",
		title_pos = "center",
		enter = true,
		bufhidden = "hide",
		height = math.floor(vim.o.lines * opts.window.floating_height),
		width = math.floor(vim.o.columns * opts.window.floating_width),
		modifiable = float_opts.modifiable ~= nil and float_opts.modifiable or true,
		win_options = {
			wrap = true,
			number = false,
			relativenumber = false,
			cursorline = false,
			signcolumn = "no",
			winfixbuf = true,
		},
		on_exit = function(b)
			if state.buf == b then
				state.buf = nil
			end
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
			state.floating_buf_cmd = nil
		end,
	})
	state.floating_buf = buf

	local jid
	local chan
	if float_opts.interactive then
		vim.api.nvim_set_current_win(win)
		vim.api.nvim_win_set_buf(win, state.floating_buf)
		jid = vim.fn.jobstart(cmd, {
			term = true,
			cwd = vim.fn.getcwd(),
			env = {
				TERM = "xterm-256color",
				PAGER = "cat",
				DELTA_PAGER = "cat",
				COLORTERM = "truecolor",
			},
			on_exit = function(_, exit_code)
				vim.schedule(function()
					if float_opts.on_exit then
						float_opts.on_exit(exit_code)
					end
					local parts = type(cmd) == "string" and vim.split(cmd, "%s+") or cmd
					state.floating_buf_cmd = parts[2] or nil
					if state.floating_buf and vim.api.nvim_buf_is_valid(state.floating_buf) then
						M.close_floating_buffer()
					end
					vim.cmd("stopinsert")
				end)
			end,
		})
		state.floating_chan = jid
		vim.cmd("startinsert")
	else
		-- Create new terminal channel
		chan = vim.api.nvim_open_term(state.floating_buf, {})
		if not chan or chan <= 0 then
			vim.notify("Failed to create terminal channel", vim.log.levels.ERROR)
			return
		end
		state.floating_chan = chan

		-- Move cursor to top before output arrives
		vim.api.nvim_win_set_cursor(win, { 1, 0 })

		jid = vim.fn.jobstart(cmd, {
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
			on_exit = function(_, exit_code)
				if float_opts.on_exit then
					float_opts.on_exit(exit_code)
				end
				vim.schedule(function()
					if not state.floating_buf or not vim.api.nvim_buf_is_valid(state.floating_buf) then
						return
					end
					-- Store the subcommand on successful exit
					if exit_code == 0 then
						state.floating_buf_cmd = cmd[2]
					end
					-- Make the bufer optionally not modifiable
					if not float_opts.keep_modifiable then
						buffer.set_modifiable(state.floating_buf, false)
					end
					buffer.stop_insert(state.floating_buf)
					-- Restore the cursor position now that the command is done
					if state.cursor_restore_pos then
						M.restore_cursor_position()
					end
				end)
			end,
		})
	end

	if not jid or jid <= 0 then
		local cmd_text = type(cmd) == "string" and cmd or table.concat(cmd, " ")
		if chan then
			vim.api.nvim_chan_send(chan, "Failed to start command: " .. cmd_text .. "\r\n")
		else
			vim.notify("Failed to start command: " .. cmd_text, vim.log.levels.ERROR)
		end
		state.floating_chan = nil
	else
		state.floating_job_id = jid
	end

	-- Set keymaps only if they haven't been set for this buffer
	if not vim.b[state.floating_buf].jj_keymaps_set then
		-- Interactive terminals need their native editing keys; rendered output does not.
		local default_keymaps = float_opts.interactive and {} or default_output_keymaps()

		-- Merge default keymaps with provided keymaps
		if keymaps and #keymaps > 0 then
			for _, km in ipairs(keymaps) do
				table.insert(default_keymaps, km)
			end
		end

		if not float_opts.interactive then
			remove_prompt_keymaps(state.floating_buf)
		end

		buffer.set_keymaps(state.floating_buf, default_keymaps)
		vim.b[state.floating_buf].jj_keymaps_set = true
	end
end

--- Run a command and show it's output in a terminal buffer
--- If a previous command already existed it smartly reuses the buffer cleaning the previous output
--- @param cmd string[] The command to run in the terminal buffer
--- @param keymaps jj.core.buffer.keymap[]|nil Additional keymaps to set for this command buffer
--- @return integer|nil buf The buffer handle, or nil on failure
function M.run(cmd, keymaps)
	if opts.window.type == "floating" then
		local subcmd = (type(cmd) == "string" and vim.split(cmd, " ") or cmd)[2]
		subcmd = subcmd:sub(1, 1):upper() .. subcmd:sub(2)

		M.run_floating(cmd, keymaps, {
			title = " JJ " .. subcmd .. " ",
		})
		state.buf = state.floating_buf

		return state.floating_buf
	end

	if type(cmd) == "string" then
		cmd = { cmd }
	end
	local jj_cmd = require("jj.cmd")
	keymaps = jj_cmd.merge_keymaps(keymaps or {}, jj_cmd.terminal_keymaps())

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
	local full_size = opts.window.type == "hsplit" and vim.o.lines or vim.o.columns
	state.buf = buffer.create({
		split = buffer.resolve_split(opts.window.type),
		size = math.floor(full_size * opts.window.split_size),
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
	vim.wo[win].winfixbuf = true

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
		buffer.set_keymaps(state.buf, default_output_keymaps())
		vim.b[state.buf].jj_keymaps_set = true
	end

	remove_prompt_keymaps(state.buf)

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
--- @param cmd string[] The command to run
--- @param tool_opts? jj.ui.terminal.tooltip_opts Tooltip options
--- @return number|nil buf Buffer handle, or nil on failure
--- @return number|nil win Window handle, or nil on failure
function M.run_tooltip(cmd, tool_opts)
	tool_opts = tool_opts or {}

	-- Clean up previous state if invalid
	if state.tooltip_buf and not vim.api.nvim_buf_is_valid(state.tooltip_buf) then
		state.tooltip_buf = nil
		state.tooltip_win = nil
		state.tooltip_chan = nil
		state.tooltip_job_id = nil
	end

	-- Stop any running job first
	if state.tooltip_job_id then
		vim.fn.jobstop(state.tooltip_job_id)
		state.tooltip_job_id = nil
	end

	-- Close previous channel
	if state.tooltip_chan then
		vim.fn.chanclose(state.tooltip_chan)
		state.tooltip_chan = nil
	end

	-- Wipe old buffer if it exists
	if state.tooltip_buf and vim.api.nvim_buf_is_valid(state.tooltip_buf) then
		vim.api.nvim_buf_delete(state.tooltip_buf, { force = true })
		state.tooltip_buf = nil
	end

	local height = tool_opts.height
	if height then
		local cursor_screen_row = vim.fn.screenrow()
		local available = vim.o.lines - cursor_screen_row - 2
		height = math.min(height, math.max(available, 1))
	end

	local width = tool_opts.width
	if width then
		local cursor_screen_col = vim.fn.screencol()
		local available = vim.o.columns - cursor_screen_col - 2
		width = math.min(width, math.max(available, 1))
	end

	state.tooltip_buf, state.tooltip_win = buffer.create_float({
		title = tool_opts.title or " JJ ",
		title_pos = "center",
		enter = tool_opts.enter or false,
		bufhidden = "wipe",
		relative = "cursor",
		row = 1,
		col = 0,
		width = width,
		height = height,
		zindex = 51,
		win_options = {
			wrap = true,
			number = false,
			relativenumber = false,
			cursorline = false,
			signcolumn = "no",
			winfixbuf = true,
		},
	})

	state.tooltip_chan = vim.api.nvim_open_term(state.tooltip_buf, {})
	if not state.tooltip_chan or state.tooltip_chan <= 0 then
		vim.notify("Failed to create terminal channel", vim.log.levels.ERROR)
		vim.api.nvim_buf_delete(state.tooltip_buf, { force = true })
		return nil, nil
	end

	state.tooltip_job_id = vim.fn.jobstart(cmd, {
		pty = true,
		width = vim.api.nvim_win_get_width(state.tooltip_win),
		height = vim.api.nvim_win_get_height(state.tooltip_win),
		env = {
			TERM = "xterm-256color",
			PAGER = "cat",
			DELTA_PAGER = "cat",
			COLORTERM = "truecolor",
		},
		on_stdout = function(_, data)
			if not state.tooltip_buf or not vim.api.nvim_buf_is_valid(state.tooltip_buf) then
				return
			end
			local output = table.concat(data, "\n")
			vim.api.nvim_chan_send(state.tooltip_chan, output)
		end,
		on_exit = function()
			vim.schedule(function()
				if state.tooltip_buf and vim.api.nvim_buf_is_valid(state.tooltip_buf) then
					buffer.set_modifiable(state.tooltip_buf, false)
					buffer.stop_insert(state.tooltip_buf)
				end
			end)
		end,
	})

	if state.tooltip_job_id <= 0 then
		vim.api.nvim_chan_send(state.tooltip_chan, "Failed to start command: " .. cmd .. "\r\n")
		return state.tooltip_buf, state.tooltip_win
	end

	vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
		buffer = state.tooltip_buf,
		once = true,
		callback = function()
			if state.tooltip_chan then
				pcall(vim.fn.chanclose, state.tooltip_chan)
			end
			if state.tooltip_job_id then
				pcall(vim.fn.jobstop, state.tooltip_job_id)
			end

			-- Clean the state when closing
			state.tooltip_buf = nil
			state.tooltip_win = nil
			state.tooltip_chan = nil
			state.tooltip_job_id = nil
		end,
	})

	vim.keymap.set("n", "<Esc>", function()
		M.close_tooltip()
		-- Focus the log window before restoring cursor position
		if state.buf then
			local log_win = vim.fn.bufwinid(state.buf)
			if log_win ~= -1 then
				vim.api.nvim_set_current_win(log_win)
			end
		end
		M.restore_cursor_position()
	end, { buffer = state.tooltip_buf, silent = true })
	vim.keymap.set("n", "q", function()
		M.close_tooltip()
		-- Focus the log window before restoring cursor position
		if state.buf then
			local log_win = vim.fn.bufwinid(state.buf)
			if log_win ~= -1 then
				vim.api.nvim_set_current_win(log_win)
			end
		end
		M.restore_cursor_position()
	end, { buffer = state.tooltip_buf, silent = true })

	-- Close when cursor moves in other windows (unless suppress flag is set)
	state.tooltip_close_autocmd = vim.api.nvim_create_autocmd("CursorMoved", {
		callback = function()
			if
				state.tooltip_buf
				and vim.api.nvim_buf_is_valid(state.tooltip_buf)
				and vim.api.nvim_win_is_valid(state.tooltip_win)
				and vim.api.nvim_get_current_win() ~= state.tooltip_win
			then
				-- Don't close if the keep open flag is set (e.g., when opening floating diff from tooltip)
				if vim.b[state.tooltip_buf].jj_keep_open then
					return
				end
				M.close_tooltip()
			end
		end,
	})

	if tool_opts.keymaps and #tool_opts.keymaps > 0 then
		buffer.set_keymaps(state.tooltip_buf, tool_opts.keymaps)
	end

	return state.tooltip_buf, state.tooltip_win
end

--- Whether or not to keep the tooltip open instead of autoclosing
--- @param keep_open boolean
function M.keep_tooltip_open(keep_open)
	vim.b[state.tooltip_buf].jj_keep_open = keep_open
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

return M
