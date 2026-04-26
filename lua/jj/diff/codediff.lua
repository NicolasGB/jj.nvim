local utils = require("jj.utils")
local file = require("jj.file")

---@type jj.diff
local diff = require("jj.diff")

---@type {dirs: string[], files: string[]}[]
local pending_launches = {}
---@type table<number, {dirs: string[], files: string[]}>
local artifacts_by_tab = {}
local temp_cleanup_registered = false

local function cleanup_artifacts(artifacts)
	if not artifacts then
		return
	end

	for _, file_path in ipairs(artifacts.files or {}) do
		local bufnr = vim.fn.bufnr(file_path)
		if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
			pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
		end
	end

	for _, dir_path in ipairs(artifacts.dirs or {}) do
		vim.fn.delete(dir_path, "rf")
	end
end

local function register_cleanup_hooks()
	if temp_cleanup_registered then
		return
	end
	temp_cleanup_registered = true

	local group = vim.api.nvim_create_augroup("JJCodediffTempCleanup", { clear = true })

	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "CodeDiffOpen",
		callback = function(args)
			local artifacts = table.remove(pending_launches, 1)
			if not artifacts then
				return
			end
			local tabpage = (args.data and args.data.tabpage) or vim.api.nvim_get_current_tabpage()
			artifacts_by_tab[tabpage] = artifacts
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "CodeDiffClose",
		callback = function(args)
			local tabpage = (args.data and args.data.tabpage) or vim.api.nvim_get_current_tabpage()
			local artifacts = artifacts_by_tab[tabpage]
			if artifacts then
				cleanup_artifacts(artifacts)
				artifacts_by_tab[tabpage] = nil
			end
		end,
	})

	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			for _, artifacts in pairs(artifacts_by_tab) do
				cleanup_artifacts(artifacts)
			end
			for _, artifacts in ipairs(pending_launches) do
				cleanup_artifacts(artifacts)
			end
			artifacts_by_tab = {}
			pending_launches = {}
		end,
	})
end

--- Write text lines to a temp file while preserving filename/extension for filetype detection.
--- @param original_path string
--- @param lines string[]
--- @param had_eol boolean
--- @return string|nil file_path
--- @return string|nil dir_path
local function write_temp_file_like(original_path, lines, had_eol)
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p")

	local basename = vim.fs.basename(original_path or "")
	if not basename or basename == "" then
		basename = "jj-codediff.tmp"
	end

	local path = dir .. "/" .. basename
	local fh = io.open(path, "w")
	if not fh then
		vim.fn.delete(dir, "rf")
		return nil, nil
	end
	fh:write(table.concat(lines, "\n"))
	if had_eol then
		fh:write("\n")
	end
	fh:close()

	return path, dir
end

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

	--- Omit the commit id when left is the current revision,
	--- allowing codediff to use the actual file instead of a virtual buffer.
	local commit_id_current = utils.get_current_commit_id()
	if commit_id_current == commit_id_left then
		vim.cmd(string.format("CodeDiff %s", commit_id_right))
		return
	end

	vim.cmd(string.format("CodeDiff %s %s", commit_id_right, commit_id_left))
end

local function diff_two_changes_with_history(left, right)
	local commit_id_left = utils.get_commit_id(left)
	if commit_id_left == nil then
		return
	end

	local commit_id_right = utils.get_commit_id(right)
	if commit_id_right == nil then
		return
	end

	-- test
	vim.cmd(string.format("CodeDiff history %s..%s", commit_id_right, commit_id_left))
end

-----------------------------------------------------------------------
-- Codediff Backend
-----------------------------------------------------------------------

diff.register_backend("codediff", {
	diff_current = function(opts)
		if not utils.has_dependency("codediff") then
			return
		end

		local buf_name = vim.api.nvim_buf_get_name(0)
		local change_id, jj_path = utils.parse_jj_uri(buf_name)
		local revset = opts.rev or (change_id and (change_id .. "-")) or "@-"

		-- For jj:// buffers, compare the current in-memory buffer against <revset> for the same file.
		if change_id and not opts.path then
			local path = jj_path
			if not path or path == "" then
				utils.notify("Invalid jj:// buffer path", vim.log.levels.ERROR)
				return
			end

			local base_lines, base_had_eol, ok_read = file.get_file_content(revset, path)
			if not ok_read then
				utils.notify(string.format("Could not read `%s` from `%s` for CodeDiff", path, revset), vim.log.levels.ERROR)
				return
			end
			local cur_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
			local cur_had_eol = vim.bo[0].eol

			local base_file, base_dir = write_temp_file_like(path, base_lines, base_had_eol)
			local cur_file, cur_dir = write_temp_file_like(path, cur_lines, cur_had_eol)
			if not base_file or not cur_file or not base_dir or not cur_dir then
				if base_dir then
					vim.fn.delete(base_dir, "rf")
				end
				if cur_dir then
					vim.fn.delete(cur_dir, "rf")
				end
				utils.notify("Failed to create temporary files for CodeDiff", vim.log.levels.ERROR)
				return
			end

			register_cleanup_hooks()
			local artifacts = {
				dirs = { base_dir, cur_dir },
				files = { base_file, cur_file },
			}
			table.insert(pending_launches, artifacts)

			local ok_cmd, err = pcall(function()
				vim.cmd(
					string.format("CodeDiff file %s %s", vim.fn.fnameescape(base_file), vim.fn.fnameescape(cur_file))
				)
			end)

			if not ok_cmd then
				-- remove the just-enqueued launch so the next CodeDiffOpen doesn't consume it
				if pending_launches[#pending_launches] == artifacts then
					table.remove(pending_launches)
				else
					for i = #pending_launches, 1, -1 do
						if pending_launches[i] == artifacts then
							table.remove(pending_launches, i)
							break
						end
					end
				end

				cleanup_artifacts(artifacts)
				utils.notify(err or "Could not launch CodeDiff", vim.log.levels.ERROR)
			end

			return
		end

		local commit_id = utils.get_commit_id(revset)
		if not commit_id then
			return
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

	diff_history_revisions = function(opts)
		if not utils.has_dependency("codediff") then
			return
		end

		diff_two_changes_with_history(opts.left, opts.right)
	end,
})
