--- @class jj.ui.editor
local M = {}

local buffer = require("jj.core.buffer")

--- @class jj.ui.editor.opts
--- @field auto_insert? boolean Smart insert: enter insert mode when description is empty, stay in normal mode when one exists
--- @field highlights? jj.ui.editor.highlights
--- @field window? jj.ui.editor.window

--- @class jj.ui.editor.highlights
---@field added? table Highlight settings for added lines
---@field modified? table Highlight settings for modified lines
---@field deleted? table Highlight settings for deleted lines
---@field renamed? table Highlight settings for renamed lines

--- @class jj.ui.editor.window
--- @field type? "hsplit"|"vsplit"|"floating"|"tab" Type of window the terminal is displayed in
--- @field split_size? number Size % of the split window, either height (hsplit) or width (vsplit) (between 0.1 and 1.0)
--- @field floating_width? number Width % of the floating window (between 0.1 and 1.0)
--- @field floating_height? number Height % of the floating window (between 0.1 and 1.0)

--- @type jj.ui.editor.opts
M.opts = {
	highlights = {
		-- Only init this one by default since it's not handled natively by neovim
		renamed = { fg = "#d29922", ctermfg = "Yellow" },
	},
	auto_insert = true,
}

--- Private module state to track highlights initialization
local highlights_initialized = false

-- Initialize highlight groups once
local function init_highlights()
	if highlights_initialized then
		return
	end

	-- Override the highlight groups if user provided custom settings
	if M.opts.highlights.added then
		vim.api.nvim_set_hl(0, "Added", M.opts.highlights.added)
	end

	if M.opts.highlights.modified then
		vim.api.nvim_set_hl(0, "Changed", M.opts.highlights.modified)
	end

	if M.opts.highlights.deleted then
		vim.api.nvim_set_hl(0, "Removed", M.opts.highlights.deleted)
	end

	-- Neovim's jj syntax uses jjRenamed for renamed files.
	-- Also define Renamed for backward compatibility with existing user configs.
	if M.opts.highlights.renamed then
		vim.api.nvim_set_hl(0, "jjRenamed", M.opts.highlights.renamed)
	end

	highlights_initialized = true
end

--- Setup function to configure highlights and other options
---@param user_opts? jj.ui.editor.opts Configuration options
function M.setup(user_opts)
	M.opts = vim.tbl_deep_extend("force", M.opts, user_opts or {})

	-- Reset highlights flag to force re-initialization with new highlights
	if highlights_initialized then
		highlights_initialized = false
		init_highlights()
	end
end

---@param initial_text string[] Lines to initialize the buffer with
---@param on_write fun(buf: string[])? Optional callback called with user text on buffer write
---@param on_unload? fun(buf: string[])? Optional callback  with user text called when the buffer is closed
---@param keymaps? jj.core.buffer.keymap[] Optional keymaps for the buffer
function M.open_editor(initial_text, on_write, on_unload, keymaps)
	-- Initialize highlight groups once
	init_highlights()

	-- Create a namespace for explicit renamed-line highlighting (independent of syntax file support)
	local ns_id = vim.api.nvim_create_namespace("jj_describe_highlights")

	-- Apply explicit highlight for renamed entries in JJ header lines.
	-- Example line: "JJ:   R path/to/file"
	local function apply_highlights(buf)
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end

		vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

		for i, line in ipairs(lines) do
			local status_pos = line:match("^JJ:%s+()R%s")
			if status_pos then
				-- Highlight only the status letter (R), like A/M/D syntax groups do.
				vim.api.nvim_buf_set_extmark(buf, ns_id, i - 1, status_pos - 1, {
					end_col = status_pos,
					hl_group = "jjRenamed",
					priority = 200,
				})
			end
		end
	end

	-- Create buffer
	local buf = M.create_buffer()
	-- Set keymaps before setting content to avoid triggering them during setup
	buffer.set_keymaps(buf, keymaps or {})

	-- Set buffer content
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_text)
	apply_highlights(buf)

	-- Keep explicit highlights up-to-date while editing
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufEnter" }, {
		buffer = buf,
		callback = function()
			apply_highlights(buf)
		end,
	})

	-- Smart insert mode: insert when description is empty, normal mode otherwise
	if M.opts.auto_insert then
		vim.schedule(function()
			if not vim.api.nvim_buf_is_valid(buf) then
				return
			end
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			local desc = require("jj.utils").extract_description_from_describe(lines)
			if not desc or desc == "" then
				vim.cmd("startinsert")
			end
		end)
	end

	-- Handle :w and :wq commands
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = buf,
		callback = function()
			-- Get current buffer lines
			local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			-- Update the last written lines variable
			vim.b[buf].jj_last_written_lines = buf_lines
			vim.bo[buf].modified = false
			-- Call the on_write callback if provided
			if on_write then
				on_write(buf_lines)
			end
		end,
	})

	-- Register the on_close callback
	if on_unload then
		vim.api.nvim_create_autocmd("BufWipeout", {
			buffer = buf,
			callback = function()
				local last_written = vim.b[buf].jj_last_written_lines
				on_unload(last_written)
			end,
		})
	end
end

--- Create the buffer based on the module options.
--- @return number buf Buffer number of the created buffer
function M.create_buffer()
	if M.opts.window.type == "floating" then
		local buf, _ = buffer.create_float({
			title = "JJ editor",
			title_pos = "center",
			filetype = "jjdescription",
			buftype = "acwrite",
			bufhidden = "wipe",
			enter = true,
			modifiable = true,
			height = math.floor(vim.o.lines * M.opts.window.floating_height),
			width = math.floor(vim.o.columns * M.opts.window.floating_width),
			win_options = {
				wrap = true,
				number = false,
				relativenumber = false,
				cursorline = false,
				signcolumn = "no",
				winfixbuf = true,
			},
		})

		return buf
	else
		-- Get the lines/columns based on the direction of the split
		local full_size = M.opts.window.type == "hsplit" and vim.o.lines or vim.o.columns

		return buffer.create({
			name = "jj:///DESCRIBE_EDITMSG",
			filetype = "jjdescription",
			buftype = "acwrite",
			bufhidden = "wipe",
			modifiable = true,
			split = buffer.resolve_split(M.opts.window.type),
			size = math.floor(full_size * M.opts.window.split_size),
		})
	end
end

return M
