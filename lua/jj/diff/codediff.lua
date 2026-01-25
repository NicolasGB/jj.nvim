local utils = require("jj.utils")

---@type jj.diff
local diff = require("jj.diff")

--- Givewn two changes, show their diff using codediff
--- @param left string
--- @param right string
local function diff_two_changes(left, right)
	local commit_id_left = utils.get_commit_id(left)
	if commit_id_left == nil then
		return
	end

	local commit_id_right = utils.get_commit_id(right)
	if commit_id_right == nil then
		return
	end

	vim.cmd(string.format("CodeDiff %s %s", commit_id_right, commit_id_left))
end

-----------------------------------------------------------------------
-- Codediff Backend
-----------------------------------------------------------------------

diff.register_backend("codediff", {
	diff_current = function(opts)
		if not utils.has_dependency("codediff") then
			return
		end

		-- Extract the commit id from opts.rev
		local commit_id = "HEAD~1"
		if opts.rev then
			local t_commit_id = utils.get_commit_id(opts.rev)
			if t_commit_id == nil then
				return
			end
			commit_id = t_commit_id
		end

		vim.cmd(string.format("CodeDiff file %s", commit_id))
	end,

	show_revision = function(opts)
		if not utils.has_dependency("codediff") then
			return
		end

		-- When comparing a revision we always compare it to it's parent to get the diff
		local right = string.format("%s-", opts.rev)

		diff_two_changes(opts.rev, right)
	end,

	diff_revisions = function(opts)
		if not utils.has_dependency("codediff") then
			return
		end

		diff_two_changes(opts.left, opts.right)
	end,
})
