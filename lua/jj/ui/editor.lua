--- @class jj.ui.editor
local M = {}

--- @class jj.ui.editor.highlights
---@field added table Highlight settings for added lines
---@field modified table Highlight settings for modified lines
---@field deleted table Highlight settings for deleted lines
---@field renamed table Highlight settings for renamed lines

M.highlights = {
	added = { fg = "#3fb950", ctermfg = "Green" },
	modified = { fg = "#56d4dd", ctermfg = "Cyan" },
	deleted = { fg = "#f85149", ctermfg = "Red" },
	renamed = { fg = "#d29922", ctermfg = "Yellow" },
}
M.highlights_initialized = false

-- Initialize highlight groups once
local function init_highlights()
	if M.highlights_initialized then
		return
	end

	vim.api.nvim_set_hl(0, "JJComment", { link = "Comment" })
	vim.api.nvim_set_hl(0, "JJAdded", M.highlights.added)
	vim.api.nvim_set_hl(0, "JJModified", M.highlights.modified)
	vim.api.nvim_set_hl(0, "JJDeleted", M.highlights.deleted)
	vim.api.nvim_set_hl(0, "JJRenamed", M.highlights.renamed)

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
function M.open_editor(initial_text, on_done)
	-- Initialize highlight groups once
	init_highlights()

	-- Create a horizontal split at the bottom, half the screen height
	local height = math.floor(vim.o.lines / 2)
	vim.cmd(string.format("%dsplit", height))

	-- Create a new unlisted, scratch buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, "jujutsu:///DESCRIBE_EDITMSG")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_text)
	vim.api.nvim_win_set_buf(0, buf)

	-- Configure buffer options
	vim.bo[buf].buftype = "acwrite" -- Allow custom write handling
	vim.bo[buf].bufhidden = "wipe" -- Automatically wipe buffer when hidden
	vim.bo[buf].swapfile = false -- Disable swapfile
	vim.bo[buf].modifiable = true -- Allow editing

	-- Create a namespace for our highlights
	local ns_id = vim.api.nvim_create_namespace("jj_describe_highlights")

	-- Function to apply highlights to the buffer
	local function apply_highlights()
		-- Clear existing highlights
		vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

		-- Get all lines
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

		for i, line in ipairs(lines) do
			local line_idx = i - 1 -- 0-indexed

			-- First, check if line starts with JJ: and highlight it as comment
			if line:match("^JJ:") then
				-- Highlight the "JJ:" prefix as comment (first 3 characters)
				vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, 0, {
					end_col = 3,
					hl_group = "JJComment",
				})

				-- Then check for status indicators and highlight the rest of the line
				local status_pos = line:find("[MADRC] ", 4) -- Find status after "JJ:"
				if status_pos then
					local status = line:sub(status_pos, status_pos) -- Get the status character
					local hl_group = nil

					if status == "A" or status == "C" then
						hl_group = "JJAdded"
					elseif status == "M" then
						hl_group = "JJModified"
					elseif status == "D" then
						hl_group = "JJDeleted"
					elseif status == "R" then
						hl_group = "JJRenamed"
					end

					if hl_group then
						-- Highlight from the status character to the end of the line
						vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, status_pos - 1, {
							end_col = #line,
							hl_group = hl_group,
						})
					else
						-- No status, keep rest as comment
						vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, 3, {
							end_col = #line,
							hl_group = "JJComment",
						})
					end
				else
					-- No status indicator, highlight rest of line as comment
					vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, 3, {
						end_col = #line,
						hl_group = "JJComment",
					})
				end
			end
		end
	end

	-- Apply highlights initially
	apply_highlights()

	-- Reapply highlights when text changes
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = buf,
		callback = apply_highlights,
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

	-- Add keymap to close the buffer with 'q' in normal mode
	vim.keymap.set(
		"n",
		"q",
		"<cmd>close!<CR>",
		{ buffer = buf, noremap = true, silent = true, desc = "Close describe buffer" }
	)

	-- Add keymap to close the buffer with '<Esc>' in normal mode
	vim.keymap.set(
		"n",
		"<Esc>",
		"<cmd>close!<CR>",
		{ buffer = buf, noremap = true, silent = true, desc = "Close describe buffer" }
	)
end

return M
