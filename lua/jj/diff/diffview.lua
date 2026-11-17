local utils = require("jj.utils")
local diff = require("jj.diff")

-- Diffview's Lua entry points accept argv and -C{path}. Keeping the directory
-- and file filter as individual arguments also preserves spaces in paths.
local function open(opts, left, right, history)
	if not utils.has_dependency("diffview") then
		return
	end
	local left_id = utils.get_commit_id(left, opts.cwd)
	local right_id = right and utils.get_commit_id(right, opts.cwd)
	if not left_id or (right and not right_id) then
		return
	end
	local range = right_id and (right_id .. ".." .. left_id) or left_id
	local args = { "-C" .. opts.cwd, history and ("--range=" .. range) or range }
	if opts.path then
		vim.list_extend(args, { "--", utils.resolve_cwd_path(opts.path, opts.cwd) })
	end
	if history then
		require("diffview").file_history(nil, args)
	else
		require("diffview").open(args)
	end
	return true
end

diff.register_backend("diffview", {
	diff_current = function(opts)
		local change_id, jj_path = utils.parse_jj_uri(vim.api.nvim_buf_get_name(0))
		local rev = opts.rev or (change_id and (change_id .. "-")) or "@-"
		local path, err = utils.normalize_relative_path(opts.path or jj_path or "%", opts.cwd)
		if not path then
			utils.notify(err or "Could not resolve file path for Diffview", vim.log.levels.ERROR)
			return
		end
		if open(vim.tbl_extend("force", opts, { path = path }), rev) then
			vim.cmd("DiffviewToggleFiles")
		end
	end,
	show_revision = function(opts)
		open(opts, opts.rev, opts.rev .. "-")
	end,
	diff_revisions = function(opts)
		open(opts, opts.left, opts.right)
	end,
	diff_history_revisions = function(opts)
		open(opts, opts.left, opts.right, true)
	end,
})
