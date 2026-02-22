--- @class jj.cmd.browse
local M = {}

local utils = require("jj.utils")

--- Build a line anchor for a hosted-file URL.
--- GitHub uses `#L<start>-L<end>` for ranges; GitLab uses `#L<start>-<end>`.
--- @param host string|nil Remote host name (e.g. github.com)
--- @param line1 integer|nil 1-indexed start line
--- @param line2 integer|nil 1-indexed end line
--- @return string anchor URL fragment (including leading `#`), or empty string
local function build_anchor(host, line1, line2)
	if not line1 then
		return ""
	end

	-- GitHub: #L1-L2, GitLab: #L1-2
	local is_gitlab = host and host:match("gitlab")
	if line2 and line2 ~= line1 then
		if is_gitlab then
			return string.format("#L%d-%d", line1, line2)
		end
		return string.format("#L%d-L%d", line1, line2)
	end

	return string.format("#L%d", line1)
end

--- Build a browser URL for a file in a repo.
--- Falls back to GitHub-style routing unless host is recognized.
--- @param base_repo_url string HTTPS base repo URL (e.g. https://host/owner/repo)
--- @param host string Remote hostname
--- @param ref string Commit SHA (preferred) or branch-like reference
--- @param path string Repo-relative file path
--- @param line1 integer|nil 1-indexed start line
--- @param line2 integer|nil 1-indexed end line
--- @return string url
local function build_browse_url(base_repo_url, host, ref, path, line1, line2)
	local encoded_path = utils.url_encode_path(path)
	local anchor = build_anchor(host, line1, line2)

	if host and host:match("gitlab") then
		return string.format("%s/-/blob/%s/%s%s", base_repo_url, ref, encoded_path, anchor)
	end

	if host and (host:match("gitea") or host:match("forgejo")) then
		-- Use commit URLs only when ref looks like a SHA; otherwise use branch URLs.
		local is_sha = type(ref) == "string" and ref:match("^[0-9a-fA-F]+$") and #ref >= 7
		local kind = is_sha and "commit" or "branch"
		return string.format("%s/src/%s/%s/%s%s", base_repo_url, kind, ref, encoded_path, anchor)
	end

	-- GitHub-style default
	return string.format("%s/blob/%s/%s%s", base_repo_url, ref, encoded_path, anchor)
end

--- Open current file on remote at current line / selected range
--- @param opts? {line1?: number, line2?: number, range?: number, args?: string, fargs?: string[]}
function M.browse(opts)
	if not utils.ensure_jj() then
		return
	end

	local abs_path = vim.api.nvim_buf_get_name(0)
	if not utils.is_file(abs_path) then
		utils.notify("Current buffer is not a file", vim.log.levels.ERROR)
		return
	end

	local root = utils.get_jj_root()
	if not root then
		utils.notify("Not in a jj repository", vim.log.levels.ERROR)
		return
	end

	local repo_rel = utils.relpath(root, abs_path)
	if not repo_rel then
		utils.notify("File is not within jj repository root", vim.log.levels.ERROR)
		return
	end
	repo_rel = repo_rel:gsub("\\", "/")

	local line1, line2
	if opts and opts.range and opts.range > 0 and opts.line1 and opts.line2 then
		line1, line2 = opts.line1, opts.line2
	else
		line1 = vim.api.nvim_win_get_cursor(0)[1]
		line2 = line1
	end

	local revset = "@"
	if opts then
		if type(opts.args) == "string" and opts.args ~= "" then
			revset = vim.trim(opts.args)
		elseif type(opts.fargs) == "table" and #opts.fargs > 0 then
			revset = vim.trim(opts.fargs[1] or "")
		end
	end

	local remotes = utils.get_remotes()
	if remotes == nil then
		utils.notify("Failed to get git remotes", vim.log.levels.ERROR)
		return
	end
	if #remotes == 0 then
		utils.notify("No git remotes found", vim.log.levels.ERROR)
		return
	end

	local function browse_with_remote(remote)
		local base_repo_url, host = utils.normalize_remote_url(remote.url)
		if not base_repo_url or not host then
			utils.notify("Unsupported remote URL: " .. (remote.url or ""), vim.log.levels.ERROR)
			return
		end

		-- If a revset has been given the walkback is none since the user doesn't expect any walkback
		local max_walkback = 20
		if revset ~= "@" then
			max_walkback = 0
		end

		local commit_id = utils.get_pushed_commit_id(revset, remote.name, max_walkback)
		if not commit_id then
			utils.notify(
				string.format("Could not determine a remote reachable commit for %s", revset),
				vim.log.levels.ERROR
			)
			return
		end

		-- Prefer a single remote bookmark name (more readable). If there are multiple,
		-- stick to commit SHA to avoid ambiguity.
		local ref = utils.get_unique_remote_bookmark_name(commit_id, remote.name) or commit_id

		local url = build_browse_url(base_repo_url, host, ref, repo_rel, line1, line2)
		utils.open_url(url)
		utils.notify("Opening in browser", vim.log.levels.INFO, 1000)
	end

	if #remotes == 1 then
		browse_with_remote(remotes[1])
		return
	end

	vim.ui.select(remotes, {
		prompt = "Select remote to browse: ",
		format_item = function(item)
			return string.format("%s (%s)", item.name, item.url)
		end,
	}, function(choice)
		if choice then
			browse_with_remote(choice)
		end
	end)
end

function M.register_command()
	vim.api.nvim_create_user_command("Jbrowse", function(cmdopts)
		M.browse(cmdopts)
	end, {
		nargs = "?",
		range = true,
		desc = "Open current file on remote (optionally pass revset; supports visual line range)",
	})
end

return M
