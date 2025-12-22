--- @class jj.core.buffer
local M = {}

--- @class jj.core.buffer.opts
--- @field name? string Buffer name
--- @field split? "horizontal"|"vertical"|"tab"|"current" Split type (default: "horizontal")
--- @field direction? "left"|"right"|"top"|"bottom" Split direction (left/right for vertical, top/bottom for horizontal)
--- @field size? number Split size in lines/columns
--- @field modifiable? boolean Whether buffer is modifiable (default: true)
--- @field filetype? string Filetype to set
--- @field buftype? string Buffer type (e.g., "nofile", "acwrite", etc. - optional, defaults to scratch buffer)
--- @field on_exit? fun(buf: number) Callback when buffer is closed
--- @field keymaps? jj.core.buffer.keymap[] Keymaps to set on the buffer
--- @field win_options? table Window-specific options to set

--- @class jj.core.buffer.keymap
--- @field modes? string|string[] Modes for the keymap (default: "n")
--- @field mode? string Alias for modes
--- @field lhs string Left-hand side of the keymap
--- @field rhs string|fun() Right-hand side of the keymap (string or function
--- @field opts? table Additional keymap options

--- @class jj.core.buffer.float_opts
--- @field width? number Window width (default: 80% of columns)
--- @field height? number Window height (default: 80% of lines)
--- @field row? number Window row position (default: centered)
--- @field col? number Window column position (default: centered)
--- @field relative? string Relative positioning (default: "editor")
--- @field style? string Window style (default: "minimal")
--- @field border? string Border style (default: "rounded")
--- @field title? string Window title (default: none)
--- @field title_pos? string Title position (default: "center")
--- @field enter? boolean Whether to enter the window after creation (default: false)
--- @field modifiable? boolean Whether buffer is modifiable (default: true)
--- @field filetype? string Filetype to set
--- @field buftype? string Buffer type (e.g., "nofile", "acwrite", etc. - optional, defaults to scratch buffer)
--- @field bufhidden? string Buffer hidden behavior (default: "hide")
--- @field on_exit? fun(buf: number) Callback when buffer is closed
--- @field keymaps? jj.core.buffer.keymap[] Keymaps to set on the buffer
--- @field win_options? table Window-specific options to set

--- Create and configure a new buffer
--- @param opts jj.core.buffer.opts Buffer configuration options
--- @return number buf Buffer handle
--- @return number? win Window handle (nil if using current window)
function M.create(opts)
	opts = opts or {}

	local win = nil

	-- Handle window/split creation
	if opts.split == "vertical" then
		local direction = opts.direction or "right"
		local width = opts.size or math.floor(vim.o.columns / 2)
		if direction == "left" then
			vim.cmd("leftabove vsplit")
		else
			vim.cmd("vsplit")
		end
		vim.cmd(string.format("vertical resize %d", width))
		win = vim.api.nvim_get_current_win()
	elseif opts.split == "tab" then
		vim.cmd("tabnew")
		win = vim.api.nvim_get_current_win()
	elseif opts.split == "current" then
		win = vim.api.nvim_get_current_win()
	else -- horizontal (default)
		local direction = opts.direction or "bottom"
		local height = opts.size or math.floor(vim.o.lines / 2)
		if direction == "top" then
			vim.cmd("topleft split")
		else
			vim.cmd("split")
		end
		vim.cmd(string.format("horizontal resize %s", height))
		win = vim.api.nvim_get_current_win()
	end

	-- Create buffer
	local buf = vim.api.nvim_create_buf(false, true)

	-- Set buffer in window if we created/got a window
	if win then
		vim.api.nvim_win_set_buf(win, buf)
	end

	-- Set buffer name if provided (only if it doesn't already exist)
	if opts.name then
		pcall(vim.api.nvim_buf_set_name, buf, opts.name)
	end

	-- Set buffer options
	if opts.buftype then
		vim.bo[buf].buftype = opts.buftype
	end
	vim.bo[buf].modifiable = opts.modifiable ~= nil and opts.modifiable or true
	vim.bo[buf].swapfile = false
	vim.bo[buf].buflisted = false

	-- Set filetype if provided
	if opts.filetype then
		vim.bo[buf].filetype = opts.filetype
	end

	-- Set keymaps if provided
	if opts.keymaps then
		M.set_keymaps(buf, opts.keymaps)
	end

	-- Set window options
	if opts.win_options then
		for option, value in pairs(opts.win_options) do
			vim.wo[win][option] = value
		end
	end

	-- Set up cleanup autocmd if on_exit callback provided
	if opts.on_exit then
		vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
			buffer = buf,
			once = true,
			callback = function()
				opts.on_exit(buf)
			end,
		})
	end

	return buf, win
end

--- Create and configure a floating window buffer
--- @param opts jj.core.buffer.float_opts Floating window configuration options
--- @return number buf Buffer handle
--- @return number win Window handle
function M.create_float(opts)
	opts = opts or {}

	-- Default config
	local width = opts.width or math.floor(vim.o.columns * 0.8)
	local height = opts.height or math.floor(vim.o.lines * 0.8)
	local row = opts.row or math.floor((vim.o.lines - height) / 2)
	local col = opts.col or math.floor((vim.o.columns - width) / 2)

	local win_config = {
		relative = opts.relative or "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = opts.style or "minimal",
		border = opts.border or "rounded",
	}

	-- Add optional title
	if opts.title then
		win_config.title = opts.title
		win_config.title_pos = opts.title_pos or "center"
	end

	-- Create buffer
	local buf = vim.api.nvim_create_buf(false, true)

	-- Create floating window
	local win = vim.api.nvim_open_win(buf, opts.enter or false, win_config)

	-- Set buffer options
	if opts.buftype then
		vim.bo[buf].buftype = opts.buftype
	end
	vim.bo[buf].modifiable = opts.modifiable ~= nil and opts.modifiable or true
	vim.bo[buf].swapfile = false
	vim.bo[buf].buflisted = false
	if opts.bufhidden then
		vim.bo[buf].bufhidden = opts.bufhidden
	end

	-- Set filetype if provided
	if opts.filetype then
		vim.bo[buf].filetype = opts.filetype
	end

	-- Set window options
	if opts.win_options then
		for option, value in pairs(opts.win_options) do
			vim.wo[win][option] = value
		end
	end

	-- Set keymaps if provided
	if opts.keymaps then
		M.set_keymaps(buf, opts.keymaps)
	end

	-- Set up cleanup autocmd if on_exit callback provided
	if opts.on_exit then
		vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
			buffer = buf,
			once = true,
			callback = function()
				opts.on_exit(buf)
			end,
		})
	end

	-- Set up auto-resize on VimResized
	vim.api.nvim_create_autocmd("VimResized", {
		buffer = buf,
		callback = function()
			if not vim.api.nvim_win_is_valid(win) then
				return true -- Remove autocmd if window is invalid
			end

			-- Recalculate dimensions
			local new_width = opts.width or math.floor(vim.o.columns * 0.8)
			local new_height = opts.height or math.floor(vim.o.lines * 0.8)
			local new_row = opts.row or math.floor((vim.o.lines - new_height) / 2)
			local new_col = opts.col or math.floor((vim.o.columns - new_width) / 2)

			-- Update window configuration
			vim.api.nvim_win_set_config(win, {
				relative = opts.relative or "editor",
				width = new_width,
				height = new_height,
				row = new_row,
				col = new_col,
			})
		end,
	})

	return buf, win
end

--- Close/wipe a buffer safely
--- @param buf number Buffer handle
--- @param force? boolean Force close (default: true)
function M.close(buf, force)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local cmd = force ~= false and "bwipeout!" or "bwipeout"
	vim.cmd(cmd .. " " .. buf)
end

--- Add keymaps to a buffer
--- @param buf number Buffer handle
--- @param keymaps jj.core.buffer.keymap[] Array of keymap definitions
function M.set_keymaps(buf, keymaps)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	for _, keymap in ipairs(keymaps) do
		local modes = keymap.modes or keymap.mode or "n"
		local lhs = keymap.lhs or keymap[1]
		local rhs = keymap.rhs or keymap[2]
		local opts = vim.tbl_extend("force", {
			buffer = buf,
			noremap = true,
			silent = true,
		}, keymap.opts or {})
		vim.keymap.set(modes, lhs, rhs, opts)
	end
end

--- Remove keymaps from a buffer
--- @param buf number Buffer handle
--- @param keymaps jj.core.buffer.keymap[] Array of keymap definitions with modes and lhs
function M.remove_keymaps(buf, keymaps)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	for _, keymap in ipairs(keymaps) do
		local modes = keymap.modes or keymap.mode or "n"
		local lhs = keymap.lhs or keymap[1]

		local modes_list = type(modes) == "table" and modes or { modes }

		for _, mode in ipairs(modes_list) do
			pcall(vim.keymap.del, mode, lhs, { buffer = buf })
		end
	end
end

--- Set buffer as modifiable or not
--- @param buf number Buffer handle
--- @param modifiable boolean Whether buffer should be modifiable
function M.set_modifiable(buf, modifiable)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	vim.bo[buf].modifiable = modifiable
end

--- Stop insert mode if in the given buffer if the cursor is currently in that buffer
--- @param buf number Buffer handle
function M.stop_insert(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	if vim.api.nvim_get_current_buf() ~= buf then
		return
	end

	vim.cmd("stopinsert")
end

--- Start insert mode in the given buffer if the cursor is currently in that buffer
--- @param buf number Buffer handle
function M.start_insert(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	if vim.api.nvim_get_current_buf() ~= buf then
		return
	end
	vim.cmd("startinsert")
end

--- Get cursor position for a buffer
--- @param buf number Buffer handle
--- @return number[]|nil Cursor position as {line, col} or nil if buffer not visible
function M.get_cursor(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return nil
	end

	local winid = vim.fn.bufwinid(buf)
	if winid == -1 then
		return nil
	end

	return vim.api.nvim_win_get_cursor(winid)
end

--- Clamp cursor position to valid buffer bounds
--- @param buf number Buffer handle
--- @param pos number[] Cursor position as {line, col}
--- @return number[] Clamped position as {line, col}
local function clamp_cursor_position(buf, pos)
	-- Validate and clamp position to buffer bounds
	local line_count = vim.api.nvim_buf_line_count(buf)
	local target_line = math.max(1, math.min(pos[1], line_count))

	-- Get the actual line content to validate column
	local line_content = vim.api.nvim_buf_get_lines(buf, target_line - 1, target_line, false)[1] or ""
	local max_col = #line_content
	local target_col = math.max(0, math.min(pos[2], max_col))

	return { target_line, target_col }
end

--- Set cursor position for a buffer
--- Automatically validates and clamps position to buffer bounds:
--- - Line number is clamped to [1, line_count]
--- - Column is clamped to [0, line_length] based on actual line content
--- For terminal buffers, uses defer_fn to allow terminal rendering to stabilize
--- @param buf number Buffer handle
--- @param pos number[] Cursor position as {line, col} (1-indexed line, 0-indexed column)
--- @param opts? {delay?: number} Optional delay in ms for terminal buffers (default: 10)
function M.set_cursor(buf, pos, opts)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	opts = opts or {}
	local delay = opts.delay or 10

	local winid = vim.fn.bufwinid(buf)
	if winid == -1 then
		return
	end

	-- For terminal buffers, delay to allow rendering to complete
	-- Must validate position INSIDE the deferred function for terminal buffers
	-- because the buffer content may not be stable yet
	if vim.bo[buf].buftype == "terminal" or delay > 0 then
		vim.defer_fn(function()
			if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(winid) then
				return
			end

			local clamped_pos = clamp_cursor_position(buf, pos)
			vim.api.nvim_win_set_cursor(winid, clamped_pos)
		end, delay)
	else
		local clamped_pos = clamp_cursor_position(buf, pos)
		vim.api.nvim_win_set_cursor(winid, clamped_pos)
	end
end

return M
