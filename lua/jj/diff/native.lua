local utils = require("jj.utils")
local buffer = require("jj.core.buffer")
local runner = require("jj.core.runner")

local diff = require("jj.diff")
local file = require("jj.file")

--- Open a writable buffer for a specific revision of a file.
--- @param rev string The revision
--- @param path string The file path (absolute or repo-relative)
local function open_revision(rev, path)
	local raw_ids, ok = runner.execute_command(
		string.format([[jj log --no-graph -r %s -T 'change_id ++ "\n"' --quiet]], vim.fn.shellescape(rev)),
		"jj: failed to resolve revision"
	)
	if not ok then return end
	local ids = vim.split(vim.trim(raw_ids), "\n", { trimempty = true })
	if #ids ~= 1 then
		utils.notify(string.format("Revision '%s' is ambiguous", rev), vim.log.levels.ERROR)
		return
	end
	local change_id = ids[1]

	local rel_path, err = utils.normalize_repo_path(path)
	if not rel_path then
		utils.notify(err or "Could not resolve path", vim.log.levels.ERROR)
		return
	end

	local lines, had_eol = file.get_file_content(change_id, rel_path)

	local buf = vim.api.nvim_create_buf(false, true)

	local buf_name = string.format("jj://%s/%s", change_id, rel_path)
	vim.api.nvim_buf_set_name(buf, buf_name)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].eol = had_eol

	local ft = vim.filetype.match({ filename = rel_path })
	if ft then
		vim.bo[buf].filetype = ft
	end

	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].readonly = false
	vim.bo[buf].swapfile = false
	vim.bo[buf].modifiable = true

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = buf,
		callback = function()
			file.write_revision_file(buf, change_id, rel_path)
		end,
	})

	vim.bo[buf].modified = false
	vim.api.nvim_win_set_buf(0, buf)
end

-----------------------------------------------------------------------
-- Native Backend
-----------------------------------------------------------------------

diff.register_backend("native", {
	--- Opens a side-by-side diff of the current buffer against a revision.
	--- Creates a split with the revision content on the left and the current buffer on the right.
	--- Closing either side will clean up both and restore the original cursor position.
	diff_current = function(opts)
		if not utils.ensure_jj() then
			return
		end

		-- Save current state to restore after diff is closed
		local prev_buf = vim.api.nvim_get_current_buf()
		local prev_cur_pos = buffer.get_cursor(prev_buf) or { 1, 0 }

		local buf_name = vim.api.nvim_buf_get_name(0)
		local change_id, jj_path = utils.parse_jj_uri(buf_name)
		local rev = opts.rev or (change_id and (change_id .. "-")) or "@-"
		local path = opts.path or jj_path or buf_name
		local layout = opts.layout or "vertical"

		local split_fun = layout == "horizontal" and vim.cmd.split or vim.cmd.vsplit
		local orig_win = vim.api.nvim_get_current_win()

		-- Use better diff algorithm for code moves and indentation
		local saved_diffopt = vim.o.diffopt
		vim.opt.diffopt:append("algorithm:patience,indent-heuristic")

		-- Set up diff: current buffer on right, revision on left
		vim.cmd.diffthis()
		split_fun({ mods = { split = "aboveleft" } })
		open_revision(rev, path)
		vim.cmd.diffthis()

		local rev_buf = vim.api.nvim_get_current_buf()
		local augroup = vim.api.nvim_create_augroup("JJDiffCleanup" .. rev_buf, { clear = true })

		-- Cleanup closes both sides, exits diff mode, and restores cursor.
		local function cleanup()
			vim.api.nvim_del_augroup_by_id(augroup)
			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(rev_buf) then
					vim.api.nvim_buf_delete(rev_buf, { force = true })
				end
				if vim.api.nvim_win_is_valid(orig_win) then
					vim.api.nvim_set_current_win(orig_win)
					vim.cmd.diffoff()
				end
				buffer.set_cursor(prev_buf, prev_cur_pos)
				vim.o.diffopt = saved_diffopt
			end)
		end

		-- Trigger cleanup when either the revision buffer or original window is closed
		vim.api.nvim_create_autocmd({ "BufWipeout", "BufHidden" }, {
			group = augroup,
			buffer = rev_buf,
			once = true,
			callback = cleanup,
		})

		vim.api.nvim_create_autocmd("WinClosed", {
			group = augroup,
			pattern = tostring(orig_win),
			once = true,
			callback = cleanup,
		})
	end,
	show_revision = function(opts)
		local terminal = require("jj.ui.terminal")

		local cmd = string.format("jj show -r %s --quiet --no-pager", opts.rev)
		terminal.run_floating(cmd)
	end,
	diff_revisions = function(opts)
		local terminal = require("jj.ui.terminal")

		local cmd = string.format("jj diff -f %s -t %s --quiet --no-pager", opts.left, opts.right)
		terminal.run_floating(cmd)
	end,
	diff_history_revisions = function(_)
		utils.notify(
			"Diffing revisions with history mode is not supported on the `native` backend.",
			vim.log.levels.WARN
		)
	end,
})
