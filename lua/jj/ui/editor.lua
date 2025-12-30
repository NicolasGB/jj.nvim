--- @class jj.ui.editor
local M = {}

local buffer = require("jj.core.buffer")

--- @class jj.ui.editor.highlights
---@field added? table Highlight settings for added lines
---@field modified? table Highlight settings for modified lines
---@field deleted? table Highlight settings for deleted lines
---@field renamed? table Highlight settings for renamed lines

M.highlights = {
	-- Only init this one by default since it's not handled natively by neovim
	renamed = { fg = "#d29922", ctermfg = "Yellow" },
}
M.highlights_initialized = false

-- Initialize highlight groups once
local function init_highlights()
	if M.highlights_initialized then
		return
	end

	-- Override the highlight groups if user provided custom settings
	if M.highlights.added then
		vim.api.nvim_set_hl(0, "Added", M.highlights.added)
	end

	if M.highlights.modified then
		vim.api.nvim_set_hl(0, "Changed", M.highlights.modified)
	end

	if M.highlights.deleted then
		vim.api.nvim_set_hl(0, "Removed", M.highlights.deleted)
	end

	-- this one will always be executed since the default nvim highlight group does not exist for renames
	if M.highlights.renamed then
		vim.api.nvim_set_hl(0, "jjRenamed", M.highlights.renamed)
	end

	M.highlights_initialized = true
end

--- Setup function to configure highlights and other options
---@param opts? { highlights: jj.ui.editor.highlights } Configuration options
function M.setup(opts)
	opts = opts or {}

	-- Merge user highlights with defaults
	if opts.highlights then
		M.highlights = vim.tbl_deep_extend("force", M.highlights, opts.highlights)
	end

	-- Reset highlights flag to force re-initialization with new highlights
	if M.highlights_initialized then
		M.highlights_initialized = false
		init_highlights()
	end
end

---@param initial_text string[] Lines to initialize the buffer with
---@param on_done fun(buf: string[])? Optional callback called with user text on buffer write
---@param on_unload? fun()? Optional callback called when the buffer is closed
---@param keymaps? jj.core.buffer.keymap[] Optional keymaps for the buffer
function M.open_editor(initial_text, on_done, on_unload, keymaps)
	-- Initialize highlight groups once
	init_highlights()

	-- Create a namespace for our highlights
	local ns_id = vim.api.nvim_create_namespace("jj_describe_highlights")

	-- Function to apply highlights to the buffer
	local function apply_highlights(buf)
		-- Clear existing highlights
		vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

		-- Get all lines
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

		for i, line in ipairs(lines) do
			local line_idx = i - 1 -- 0-indexed

			-- First, check if line starts with JJ: and highlight it as comment
			if line:match("^JJ:") then
				-- Then check for rename status indicator
				local status_pos = line:find("[R] ", 4) -- Find status after "JJ:"
				if status_pos then
					local status = line:sub(status_pos, status_pos) -- Get the status character
					local hl_group = nil

					if status == "R" then
						hl_group = "jjRenamed"
					end

					if hl_group then
						-- Highlight from the status character to the end of the line
						vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, status_pos - 1, {
							end_col = #line,
							hl_group = hl_group,
						})
					end
				end
			end
		end
	end

	-- Create buffer
	local buf = buffer.create({
		name = "jujutsu:///DESCRIBE_EDITMSG",
		split = "horizontal",
		size = math.floor(vim.o.lines / 2),
		filetype = "jjdescription",
		buftype = "acwrite",
		modifiable = true,
		keymaps = keymaps,
	})

	-- Set buffer content
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_text)

	-- Set bufhidden after creation
	vim.bo[buf].bufhidden = "wipe"

	-- Apply highlights initially
	apply_highlights(buf)

	-- Reapply highlights when text changes
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = buf,
		callback = function()
			apply_highlights(buf)
		end,
	})

	-- Handle :w and :wq commands
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = buf,
		callback = function()
			local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			if on_done then
				on_done(buf_lines)
			end
			vim.bo[buf].modified = false
		end,
	})

	-- Register the on_close callback
	if on_unload then
		vim.api.nvim_create_autocmd("BufWipeout", {
			buffer = buf,
			callback = function()
				on_unload()
			end,
		})
	end
end

return M
