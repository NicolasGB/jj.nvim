---@class jj.diff
local M = {}

local utils = require("jj.utils")
local buffer = require("jj.core.buffer")

--- Get the content of a file at a specific revision
--- @param rev string The revision
--- @param path string The file path
--- @return table lines The file content
local function get_file_content(rev, path)
	local cmd = string.format("jj file show -r %s %s", vim.fn.shellescape(rev), vim.fn.shellescape(path))
	local content = vim.fn.system(cmd)
	local success = vim.v.shell_error == 0
	if success then
		return vim.split(content, "\n", { trimempty = true })
	else
		-- File does not exist at revision
		return {}
	end
end

--- Open a read-only buffer for a specific revision of a file
--- @param rev string The revision
--- @param path string The file path
function M.open_revision(rev, path)
	local lines = get_file_content(rev, path)

	local buf = vim.api.nvim_create_buf(false, true)

	local buf_name = string.format("jj://%s/%s", rev, path)
	vim.api.nvim_buf_set_name(buf, buf_name)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	local ft = vim.filetype.match({ filename = path })
	if ft then
		vim.bo[buf].filetype = ft
	end

	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].readonly = true
	vim.bo[buf].swapfile = false
	vim.bo[buf].modifiable = true

	vim.api.nvim_win_set_buf(0, buf)
end

---@class jj.diff.diff_opts
---@field rev string the revision to diff against

--- Open a diff split for a specific revision of the current file
--- @param split_fun function Split function for the diff
--- @param opts? jj.diff.diff_opts Any passed arguments
function M.open_diff(split_fun, opts)
	if not utils.ensure_jj() then
		return
	end

	-- Get previus cursor position
	local prev_buf = vim.api.nvim_get_current_buf()
	local prev_cur_pos = buffer.get_cursor(prev_buf)
	-- If no previous cursor position, set to start of file
	if prev_cur_pos == nil then
		prev_cur_pos = { 1, 0 }
	end

	-- Ensure opts is a table to avoid indexing nil
	opts = opts or {}
	local rev = opts.rev or "@-"
	local path = vim.api.nvim_buf_get_name(0)

	vim.cmd.diffthis()
	split_fun({ mods = { split = "aboveleft" } })
	M.open_revision(rev, path)
	vim.cmd.diffthis()

	-- Add an autocomnd to restore the buffer position to the previous one when exiting diff
	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = vim.api.nvim_get_current_buf(),
		callback = function()
			buffer.set_cursor(prev_buf, prev_cur_pos)
		end,
	})
end

-- Open a vertical diff split for a specific revision of the current file
--- @param opts? jj.diff.diff_opts Any passed arguments
function M.open_vdiff(opts)
	M.open_diff(vim.cmd.vsplit, opts)
end

-- Open a horizontal diff split for a specific revision of the current file
--- @param opts? jj.diff.diff_opts Any passed arguments
function M.open_hdiff(opts)
	M.open_diff(vim.cmd.split, opts)
end

return M
