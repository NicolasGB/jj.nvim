local runner = require("jj.core.runner")

--- @class jj.utils
local M = {
	executable_cache = {},
	dependency_cache = {},
}

-- No-op setup, but keep it for API consistency in case we need it later.
function M.setup(_) end

--- Cache for executable checks to avoid repeated system calls

--- Check if an executable exists in PATH
--- @param name string The name of the executable to check
--- @return boolean True if executable exists, false otherwise
function M.has_executable(name)
	if M.executable_cache[name] ~= nil then
		return M.executable_cache[name]
	end

	local exists = vim.fn.executable(name) == 1
	M.executable_cache[name] = exists
	return exists
end

--- Check if the dependency is currently installed
--- @param module string The dependency module
--- @return boolean
function M.has_dependency(module)
	if M.dependency_cache[module] ~= nil then
		return true
	end

	local exists, _ = pcall(require, module)
	if not exists then
		M.notify(string.format("Module %s not installed", module), vim.log.levels.ERROR)
		return false
	end

	return true
end

--- Clear the executable cache (useful for testing or if PATH changes)
function M.clear_executable_cache()
	M.executable_cache = {}
end

--- Check if jj executable exists, show error if not
--- @return boolean True if jj exists, false otherwise
function M.ensure_jj()
	if not M.has_executable("jj") then
		M.notify("jj command not found", vim.log.levels.ERROR)
		return false
	end
	return true
end

--- Check if we're in a jj repository
--- @return boolean True if in jj repo, false otherwise
function M.is_jj_repo()
	if not M.ensure_jj() then
		return false
	end

	-- We require the runner here to avoid a circular dependency loop at startup
	local _, success = runner.execute_command("jj status")
	return success
end

--- Get jj repository root path
--- @return string|nil The repository root path, or nil if not in a repo
function M.get_jj_root()
	if not M.ensure_jj() then
		return nil
	end

	-- We require the runner here to avoid a circular dependency loop at startup
	local output, success = runner.execute_command("jj root")
	if success and output then
		return vim.trim(output)
	end
	return nil
end

--- Get a list of files modified in the current jj repository.
--- @return string[] A list of modified file paths
function M.get_modified_files()
	if not M.ensure_jj() then
		return {}
	end

	-- We require the runner here to avoid a circular dependency loop at startup
	local result, success = runner.execute_command("jj diff --name-only", "Error getting diff")
	if not success or not result then
		return {}
	end

	local files = {}
	-- Split the result into lines and add each file to the table
	for file in result:gmatch("[^\r\n]+") do
		table.insert(files, file)
	end

	return files
end

---- Notify function to display messages with a title
--- @param message string The message to display
--- @param level? number The log level (default: INFO)
--- @param timeout number? The timeout duration in milliseconds (default: 3000)
function M.notify(message, level, timeout)
	level = level or vim.log.levels.INFO
	timeout = timeout or 3000
	vim.notify(message, level, { title = "JJ", timeout = timeout })
end

--- URL encode a string for use in URLs
--- @param str string The string to encode
--- @return string The URL-encoded string
function M.url_encode(str)
	return (str:gsub("([^%w%-_.~])", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

--- URL-encode a file path for use in URLs.
--- Encodes each path segment and preserves `/` separators.
--- Also normalizes Windows path separators (`\` -> `/`).
--- @param path string
--- @return string
function M.url_encode_path(path)
	path = (path or ""):gsub("\\", "/")
	local parts = vim.split(path, "/", { plain = true })
	for i, seg in ipairs(parts) do
		parts[i] = M.url_encode(seg)
	end
	return table.concat(parts, "/")
end

--- Check whether a path points to an existing file.
--- @param path string|nil
--- @return boolean
function M.is_file(path)
	if not path or path == "" then
		return false
	end
	local st = vim.uv.fs_stat(path)
	return st ~= nil and st.type == "file"
end

--- Compute a repository-relative path.
--- Returns nil if `path` is outside of `root`.
--- @param root string
--- @param path string
--- @return string|nil
function M.relpath(root, path)
	if not root or root == "" or not path or path == "" then
		return nil
	end

	local ok_norm_root, norm_root = pcall(vim.fs.normalize, root)
	local ok_norm_path, norm_path = pcall(vim.fs.normalize, path)
	if not ok_norm_root or not ok_norm_path then
		norm_root, norm_path = root, path
	end

	local ok_rel, rel = pcall(vim.fs.relpath, norm_root, norm_path)
	if ok_rel and rel and rel ~= "" and not rel:match("^%.%.") then
		return rel
	end

	local prefix = norm_root
	if not prefix:match("/$") then
		prefix = prefix .. "/"
	end
	if vim.startswith(norm_path, prefix) then
		return norm_path:sub(#prefix + 1)
	end

	return nil
end

--- Normalize a git remote URL to an HTTPS repo URL.
--- Supports:
--- - `git@host:owner/repo(.git)`
--- - `ssh://git@host/owner/repo(.git)`
--- - `https://host/owner/repo(.git)`
--- @param raw_url string
--- @return string|nil repo_url HTTPS base repo URL (no trailing .git)
--- @return string|nil host Hostname extracted from the remote
function M.normalize_remote_url(raw_url)
	if not raw_url or raw_url == "" then
		return nil, nil
	end

	raw_url = raw_url:gsub("%.git$", "")

	-- scp-like SSH: git@host:owner/repo
	if raw_url:match("^git@") then
		local host = raw_url:match("^git@([^:]+):")
		local repo_path = raw_url:match("^git@[^:]+:(.+)$")
		if host and repo_path then
			return "https://" .. host .. "/" .. repo_path, host
		end
	end

	-- ssh://git@host/owner/repo
	if raw_url:match("^ssh://") then
		local host = raw_url:match("^ssh://[^@]+@([^/]+)/") or raw_url:match("^ssh://([^/]+)/")
		local rest = raw_url:gsub("^ssh://[^@]+@", ""):gsub("^ssh://", "")
		local repo_path = rest:match("^[^/]+/(.+)$")
		if host and repo_path then
			repo_path = repo_path:gsub("%.git$", "")
			return "https://" .. host .. "/" .. repo_path, host
		end
	end

	-- HTTPS
	local host = raw_url:match("^https?://([^/]+)")
	if host then
		return raw_url, host
	end

	return nil, nil
end

--- Open a URL using the system default handler.
--- Prefers `vim.ui.open()` when available.
--- @param url string
function M.open_url(url)
	if not url or url == "" then
		return
	end

	if vim.ui and type(vim.ui.open) == "function" then
		vim.ui.open(url)
		return
	end

	if vim.fn.has("win32") == 1 then
		-- `start` is a cmd.exe builtin
		vim.fn.jobstart({ "cmd.exe", "/c", "start", "", url }, { detach = true })
		return
	end

	local open_cmd = vim.fn.has("mac") == 1 and "open" or "xdg-open"
	vim.fn.jobstart({ open_cmd, url }, { detach = true })
end

--- Best-effort unquoting of a jj `RefSymbol` rendering.
---
--- `RefSymbol` values are displayed as revset symbols, which may be quoted and
--- escaped if necessary. For browser URLs, we generally want the raw name.
---
--- This handles the common cases of surrounding single/double quotes.
--- @param s string|nil
--- @return string
function M.unquote_refsymbol(s)
	s = vim.trim(s or "")
	if s == "" then
		return ""
	end
	local first = s:sub(1, 1)
	local last = s:sub(-1)
	if (first == '"' and last == '"') or (first == "'" and last == "'") then
		s = s:sub(2, -2)
		-- Minimal unescaping (covers typical `\"` and `\\` sequences)
		s = s:gsub("\\\\", "\\"):gsub('\\"', '"'):gsub("\\'", "'")
	end
	return s
end

--- Get all bookmarks in the repository, filters out deleted bookmarks
--- @return string[] List of bookmarks, or empty list if none found
function M.get_all_bookmarks()
	-- Use a custom template to output just the bookmark names, one per line
	-- This is more reliable than parsing the default output format
	local bookmarks_output, success = runner.execute_command(
		[[jj bookmark list -T 'if(!self.remote(), name ++ if(!self.present(), " (deleted)", "") ++ "\n")']],
		"Failed to get bookmarks",
		nil,
		true
	)

	if not success or not bookmarks_output then
		return {}
	end

	-- Parse bookmarks from template output
	local bookmarks = {}
	local seen = {}
	for line in bookmarks_output:gmatch("[^\n]+") do
		local bookmark = vim.trim(line)
		if bookmark ~= "" and not seen[bookmark] then
			-- Skip bookmarks containing "Hint:" or "(deleted)"
			if not bookmark:match("Hint:") and not bookmark:match("%(deleted%)") then
				table.insert(bookmarks, bookmark)
				seen[bookmark] = true
			end
		end
	end

	return bookmarks
end

--- Get all tags in a repository
--- @return string[] List of bookmarks, or empty list if none found
function M.get_all_tags()
	-- Use a custom template to output just the bookmark names, one per line
	-- This is more reliable than parsing the default output format
	local bookmarks_output, success = runner.execute_command(
		[[jj tag list --quiet --sort committer-date- -T 'if(!self.remote(), name ++ if(!self.present(), " (deleted)", "") ++ "\n")']],
		"Failed to get bookmarks",
		nil,
		true
	)

	if not success or not bookmarks_output then
		return {}
	end

	-- Parse tags from template output
	local tags = {}
	local seen = {}
	for line in bookmarks_output:gmatch("[^\n]+") do
		local tag = vim.trim(line)
		if tag ~= "" and not seen[tag] then
			-- Skip tags containing  "(deleted)"
			if not tag:match("%(deleted%)") then
				table.insert(tags, tag)
				seen[tag] = true
			end
		end
	end

	return tags
end

--- Whether or not the repository is colocated
--- @return boolean
function M.is_colocated()
	local output, success =
		runner.execute_command("jj git colocation status ", "Failed to determine if repository is colocated", nil, true)

	if not success or not output then
		return false
	end

	return vim.startswith(vim.trim(output), "Workspace is currently colocated with Git.")
end

--- Get all bookmarks in the repository, filters out deleted bookmarks
--- @return string[] List of bookmarks, or empty list if none found
function M.get_untracked_bookmarks()
	-- Use a custom template to output just the bookmark names, one per line
	-- This is more reliable than parsing the default output format
	local bookmarks_output, success = runner.execute_command(
		[[jj bookmark list -a -T 'if(self.remote() && !self.tracked(), name ++ if(!self.present(), " (deleted)", "") ++ "\n")']],
		"Failed to get untracked bookmarks",
		nil,
		true
	)

	if not success or not bookmarks_output then
		return {}
	end

	-- Parse bookmarks from template output
	local bookmarks = {}
	local seen = {}
	for line in bookmarks_output:gmatch("[^\n]+") do
		local bookmark = vim.trim(line)
		if bookmark ~= "" and not seen[bookmark] then
			-- Skip bookmarks containing "Hint:" or "(deleted)"
			if not bookmark:match("Hint:") and not bookmark:match("%(deleted%)") then
				table.insert(bookmarks, bookmark)
				seen[bookmark] = true
			end
		end
	end

	return bookmarks
end

--- Get git remotes for the current jj repository
--- @return {name: string, url: string}[]|nil A list of remotes with name and URL
function M.get_remotes()
	local remote_list, remote_success =
		runner.execute_command("jj git remote list", "Failed to get git remote", nil, true)

	if not remote_success or not remote_list then
		return
	end

	-- Parse remotes into a table
	local remotes = {}
	for line in remote_list:gmatch("[^\n]+") do
		local name, url = line:match("^(%S+)%s+(.+)$")
		if name and url then
			table.insert(remotes, { name = name, url = url })
		end
	end

	return remotes
end

--- Open a PR/MR on the remote for a given bookmark
--- @param bookmark string The bookmark to create a PR for
function M.open_pr_for_bookmark(bookmark)
	-- Get all git remotes
	local remotes = M.get_remotes()

	if not remotes or #remotes == 0 then
		M.notify("No git remotes found", vim.log.levels.ERROR)
		return
	end

	-- Helper function to open PR for a given remote URL
	local function open_pr_with_url(raw_url)
		local repo_url, host = M.normalize_remote_url(raw_url)
		if not repo_url or not host then
			M.notify("Unsupported remote URL: " .. (raw_url or ""), vim.log.levels.ERROR)
			return
		end

		-- Construct the appropriate PR/MR URL based on the platform
		local encoded_bookmark = M.url_encode(bookmark)
		local pr_url

		if host:match("gitlab") then
			-- GitLab merge request URL
			pr_url = repo_url .. "/-/merge_requests/new?merge_request[source_branch]=" .. encoded_bookmark
		elseif host:match("gitea") or host:match("forgejo") then
			-- Gitea/Forgejo compare URL
			pr_url = repo_url .. "/compare/" .. encoded_bookmark
		else
			-- Default to GitHub-style compare URL (works for GitHub, Gitea, etc.)
			pr_url = repo_url .. "/compare/" .. encoded_bookmark .. "?expand=1"
		end

		M.open_url(pr_url)
		M.notify(string.format("Opening PR for bookmark `%s`", bookmark), vim.log.levels.INFO)
	end

	-- If only one remote, use it directly
	if #remotes == 1 then
		open_pr_with_url(remotes[1].url)
		return
	end

	-- Multiple remotes: prompt user to select
	vim.ui.select(remotes, {
		prompt = "Select remote to open PR on: ",
		format_item = function(item)
			return item.name .. " (" .. item.url .. ")"
		end,
	}, function(choice)
		if choice then
			open_pr_with_url(choice.url)
		end
	end)
end

--- Check if a given revset represents an immutable change
--- @param revset string The revset to check
--- @return boolean True if the change is immutable, false otherwise
function M.is_change_immutable(revset)
	local output, success = runner.execute_command(
		string.format("jj log --no-graph -r  '%s' -T 'immutable' --quiet", revset),
		"Error checking change immutability",
		nil,
		true
	)

	if not success or not output then
		return false
	end

	return vim.trim(output) == "true"
end

--- Check if a given revset is empty
--- @param revset string The revset to check
--- @return boolean True if the revset is empty, false otherwise
function M.is_change_empty(revset)
	local output, success = runner.execute_command(
		string.format("jj log --no-graph -r '%s' -T 'empty' --quiet", revset),
		"Error checking if revset is empty",
		nil,
		true
	)

	if not success or not output then
		return false
	end

	return vim.trim(output) == "true"
end

--- Build describe text for a given revision
--- @param revset? string The revision to describe (default: @)
--- @return string[]|nil
function M.get_describe_text(revset)
	if not revset or revset == "" then
		revset = "@"
	end

	local parser = require("jj.core.parser")
	local old_description_raw, success = runner.execute_command(
		"jj log -r " .. revset .. " --quiet --no-graph -T 'coalesce(description, \"\\n\")'",
		"Failed to get old description"
	)
	if not old_description_raw or not success then
		return nil
	end

	local status_result, success2 = runner.execute_command(
		"jj log -r " .. revset .. " --quiet --no-graph -T 'self.diff().summary()'",
		"Error getting status"
	)
	if not success2 then
		return nil
	end

	local status_files = parser.get_status_files(status_result)
	local old_description = vim.trim(old_description_raw)
	local description_lines = vim.split(old_description, "\n")
	local text = {}
	for _, line in ipairs(description_lines) do
		table.insert(text, line)
	end
	table.insert(text, "")
	table.insert(text, "JJ: Change ID: " .. revset)
	table.insert(text, "JJ: This commit contains the following changes:")
	for _, item in ipairs(status_files) do
		table.insert(text, string.format("JJ:     %s %s", item.status, item.file))
	end
	table.insert(text, "JJ:")
	table.insert(text, 'JJ: Lines starting with "JJ:" (like this one) will be removed')

	return text
end
---
--- Get the commit id from a given revision
--- @param revset string The revset to extract the commit id from
--- @return string|nil
function M.get_commit_id(revset)
	local output, success = runner.execute_command(
		string.format("jj log --no-graph -r '%s' -T 'commit_id' --quiet", revset),
		"Error extracting commit id",
		nil,
		true
	)
	-- Test quie

	if not success or not output then
		return nil
	end

	return vim.trim(output)
end

---
--- Get the commit id of the current revision
--- @return string|nil
function M.get_current_commit_id()
	local output, success = runner.execute_command(
		"jj log --no-graph -r '@' -T 'commit_id' --quiet",
		"Error extracting current revision's commit id",
		nil,
		true
	)

	if not success or not output then
		return nil
	end

	return vim.trim(output)
end

--- Return a commit id that is expected to exist on a given remote.
---
--- This is a best-effort heuristic used for browser URLs: if a commit isn't
--- reachable from the remote's bookmarks, most web UIs will 404.
---
--- Strategy:
--- - Starting from `start_revset`, walk back first-parent (`revset-`) up to
---   `max_walkback` times until the commit is contained in
---   `::remote_bookmarks(remote="<remote_name>")`.
--- - If still not found, return the commit id of `trunk()`.
---
--- @param start_revset string Starting point revset (e.g. "@")
--- @param remote_name string Remote name (e.g. "origin")
--- @param max_walkback? integer Maximum number of parents to traverse (default: 20)
--- @return string|nil commit_id
function M.get_pushed_commit_id(start_revset, remote_name, max_walkback)
	max_walkback = max_walkback or 20
	start_revset = (start_revset and start_revset ~= "") and start_revset or "@"
	remote_name = (remote_name and remote_name ~= "") and remote_name or "origin"

	-- Build a revset expression string we can embed in a template StringLiteral.
	local remote_literal = remote_name:gsub("\\", "\\\\"):gsub('"', '\\"')
	local templ = [[if(self.contained_in("::remote_bookmarks(remote='%s')"), commit_id)]]
	templ = string.format(templ, remote_literal)

	-- If `start_revset` is already a commit id (or change id), we still let jj
	-- resolve it; otherwise, treat it as a revset expression.
	local current = start_revset
	for _ = 0, max_walkback do
		-- Use a single-quoted StringLiteral for the revset, so we can keep the
		-- remote name quoted inside the revset expression.
		local cmd = string.format(
			"jj log -r %s --no-graph --quiet -T %s",
			vim.fn.shellescape(current),
			vim.fn.shellescape(templ)
		)

		local out, ok = runner.execute_command(cmd, "Error determining remote-reachable commit", nil, true)
		if ok and out and not out:match("^%s*$") then
			return vim.trim(out)
		end
		current = current .. "-"
	end

	return M.get_commit_id("trunk()")
end

--- Return a remote bookmark name pointing at `revset` on `remote_name`.
---
--- If there are 0 or multiple matching bookmarks and none of those are neither `main` nor `master`, returns nil.
--- This avoids choosing an arbitrary name when multiple bookmarks point to the
--- same commit.
---
--- @param revset string
--- @param remote_name string
--- @return string|nil bookmark_name
function M.get_unique_remote_bookmark_name(revset, remote_name)
	revset = (revset and revset ~= "") and revset or "@"
	remote_name = (remote_name and remote_name ~= "") and remote_name or "origin"

	-- Render remote bookmarks as tab-separated pairs: <remote>\t<name>\n
	local tmpl = [[self.remote_bookmarks().map(|b| b.remote() ++ "\t" ++ b.name() ++ "\n").join("")]]
	local cmd =
		string.format("jj log -r %s --no-graph --quiet -T %s", vim.fn.shellescape(revset), vim.fn.shellescape(tmpl))
	local out, ok = runner.execute_command(cmd, "Error getting remote bookmarks", nil, true)
	if not ok or not out or out:match("^%s*$") then
		return nil
	end

	local matches = {}
	for line in out:gmatch("[^\r\n]+") do
		local remote_sym, name_sym = line:match("^(.-)\t(.*)$")
		local r = M.unquote_refsymbol(remote_sym)
		local n = M.unquote_refsymbol(name_sym)
		if r == remote_name and n ~= "" then
			table.insert(matches, n)
		end
	end

	if #matches == 1 then
		return matches[1]
	elseif #matches > 1 then
		for _, name in ipairs(matches) do
			-- Unless it's main or master which takes precedence
			if name == "main" or name == "master" then
				return name
			end
		end
	end
	return nil
end

--- Extract the description from the describe text
--- @param lines string[] The lines of a described change
--- @return string|nil
function M.extract_description_from_describe(lines)
	local final_lines = {}
	for _, line in ipairs(lines) do
		if not line:match("^JJ:") then
			table.insert(final_lines, line)
		end
	end
	-- Join lines and trim leading/trailing whitespace
	local trimmed_description = table.concat(final_lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
	if trimmed_description == "" then
		-- If nothing return nil
		return
	end
	return trimmed_description
end

return M
