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

	if #remotes == 0 then
		M.notify("No git remotes found", vim.log.levels.ERROR)
		return
	end

	-- Helper function to open PR for a given remote URL
	local function open_pr_with_url(raw_url)
		-- Remove .git suffix if present
		raw_url = raw_url:gsub("%.git$", "")

		-- Convert SSH URL to HTTPS and detect platform
		local repo_url, host
		if raw_url:match("^git@") then
			-- Extract host and path from git@host:path
			host = raw_url:match("^git@([^:]+):")
			local repo_path = raw_url:match("^git@[^:]+:(.+)$")
			repo_url = "https://" .. host .. "/" .. repo_path
		else
			-- Extract host from https://host/path
			host = raw_url:match("https?://([^/]+)")
			repo_url = raw_url
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

		-- Open the URL using xdg-open or the system's default browser
		local open_cmd
		if vim.fn.has("mac") == 1 then
			open_cmd = "open"
		elseif vim.fn.has("win32") == 1 then
			open_cmd = "start"
		else
			open_cmd = "xdg-open"
		end

		vim.fn.jobstart({ open_cmd, pr_url }, { detach = true })
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
