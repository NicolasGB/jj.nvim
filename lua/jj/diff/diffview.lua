local utils = require("jj.utils")

---@type jj.diff
local diff = require("jj.diff")

-----------------------------------------------------------------------
-- Diffvew Backend
-----------------------------------------------------------------------

--- Givewn two changes, show their diff using diffview.nvim
--- @param left string
--- @param right string
local function diff_two_changes(left, right)
	-- Extract the commit id from opts.rev
	local commit_id_left = utils.get_commit_id(left)
	if commit_id_left == nil then
		return
	end
	local commit_id_right = utils.get_commit_id(right)
	if commit_id_right == nil then
		return
	end

	vim.cmd(string.format("DiffviewOpen %s..%s", commit_id_right, commit_id_left))
end

-- Register the diffview backend
diff.register_backend("diffview", {
	diff_current = function(opts)
		if not utils.has_dependency("diffview") then
			return
		end

		-- Extract the commit id from opts.rev
		local revset = opts.rev or "@-"

		local commit_id = utils.get_commit_id(revset)
		if not commit_id then
			return
		end

		vim.cmd(string.format("DiffviewOpen %s -- %%", commit_id))
		vim.cmd("DiffviewToggleFiles")
	end,
	show_revision = function(opts)
		if not utils.has_dependency("diffview") then
			return
		end

		-- When comparing a revision we always compare it to it's parent to get the diff
		local right = string.format("%s-", opts.rev)

		diff_two_changes(opts.rev, right)
	end,
	diff_revisions = function(opts)
		if not utils.has_dependency("diffview") then
			return
		end

		diff_two_changes(opts.left, opts.right)
	end,
})
