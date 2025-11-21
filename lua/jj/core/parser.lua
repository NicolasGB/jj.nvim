--- @class jj.core.parser
local M = {}

--- Parse the default command from jj config
--- @param cmd_output string The output from `jj config get ui.default-command`
--- @return table|nil args Array of command arguments, or nil if parsing fails
function M.parse_default_cmd(cmd_output)
	if not cmd_output or cmd_output == "" then
		return nil
	end

	-- Remove whitespace and parse TOML output
	local trimmed_cmd = vim.trim(cmd_output)

	-- Try to parse as TOML array: ["item1", "item2", ...]
	-- Pattern "%[(.*)%]" captures everything between square brackets
	local array_items = trimmed_cmd:match("%[(.*)%]")
	if array_items then
		local args = {}
		-- Pattern '"([^"]+)"' captures content between double quotes (non-greedy)
		for item in array_items:gmatch('"([^"]+)"') do
			table.insert(args, item)
		end
		return #args > 0 and args or nil
	else
		-- Single string value, remove surrounding quotes if present
		-- Pattern '^"?(.-)"?$' optionally matches quotes at start/end, captures content
		local single_value = trimmed_cmd:match('^"?(.-)"?$')
		return single_value and { single_value } or nil
	end
end

--- Get a list of files with their status in the current jj repository.
--- @type string status_output The output from `jj status` command
--- @return table[] A list of tables with {status = string, file = string}
function M.get_status_files(status_output)
	if not status_output then
		return {}
	end

	local files = {}
	-- Parse jj status output: "M filename", "A filename", "D filename", "R old => new"
	for line in status_output:gmatch("[^\r\n]+") do
		local status, file = line:match("^([MADRC])%s+(.+)$")
		if status and file then
			table.insert(files, { status = status, file = file })
		end
	end

	return files
end

--- Parse the current line in the jj status buffer to extract file information.
--- Handles renamed files and regular status lines.
--- @return table|nil A table with {old_path = string, new_path = string, is_rename = boolean}, or nil if parsing fails
function M.parse_file_info_from_status_line(line)
	-- Handle renamed files: "R path/{old_name => new_name}" or "R old_path => new_path"
	local rename_pattern_curly = "^R (.*)/{(.*) => ([^}]+)}"
	local dir_path, old_name, new_name = line:match(rename_pattern_curly)

	if dir_path and old_name and new_name then
		return {
			old_path = dir_path .. "/" .. old_name,
			new_path = dir_path .. "/" .. new_name,
			is_rename = true,
		}
	else
		-- Try simple rename pattern: "R old_path => new_path"
		local rename_pattern_simple = "^R (.*) => (.+)$"
		local old_path, new_path = line:match(rename_pattern_simple)
		if old_path and new_path then
			return {
				old_path = old_path,
				new_path = new_path,
				is_rename = true,
			}
		end
	end

	-- Not a rename, try regular status patterns
	local filepath
	-- Handle renamed files: "R path/{old_name => new_name}" or "R old_path => new_path"
	local rename_pattern_curly_new = "^R (.*)/{.* => ([^}]+)}"
	local dir_path_new, renamed_file = line:match(rename_pattern_curly_new)

	if dir_path_new and renamed_file then
		filepath = dir_path_new .. "/" .. renamed_file
	else
		-- Try simple rename pattern: "R old_path => new_path"
		local rename_pattern_simple_new = "^R .* => (.+)$"
		filepath = line:match(rename_pattern_simple_new)
	end

	if not filepath then
		-- jj status format: "M filename" or "A filename"
		-- Match lines that start with status letter followed by space and filename
		local pattern = "^[MAD?!] (.+)$"
		filepath = line:match(pattern)
	end

	if filepath then
		return {
			old_path = filepath,
			new_path = filepath,
			is_rename = false,
		}
	end

	return nil
end

--- Extract revision ID from a jujutsu log line
--- @param line string The log line to parse
--- @return string|nil The revision ID if found, nil otherwise
function M.get_rev_from_log_line(line)
	-- Define jujutsu symbols with their UTF-8 byte sequences
	local jj_symbols = {
		diamond = "\226\151\134", -- ◆ U+25C6
		circle = "\226\151\139", -- ○ U+25CB
		conflict = "\195\151", -- × U+00D7
	}

	local revset

	-- Try each symbol pattern
	for _, symbol in pairs(jj_symbols) do
		-- Pattern: Lines starting with symbol
		revset = line:match("^%s*" .. symbol .. "%s+(%w+)")
		if revset then
			return revset
		end

		-- Pattern: Lines with │ followed by symbol (this are the branches)
		revset = line:match("^│%s*" .. symbol .. "%s+(%w+)")
		if revset then
			return revset
		end
	end

	-- Pattern for simple ASCII symbols
	revset = line:match("^%s*[@]%s+(%w+)")
	if revset then
		return revset
	end

	return nil
end

return M
