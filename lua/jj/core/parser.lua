--- @class jj.core.parser
local M = {}

--- Parse the default command from jj config
--- @param cmd_output string The output from `jj config get ui.default-command`
--- @return table|nil args Array of command arguments, or nil if parsing fails
function M.parse_default_cmd(cmd_output)
	if not cmd_output or cmd_output == "" then
		return nil
	end

	-- Remove whitespace and strip "key = " prefix from `jj config list` output
	local trimmed_cmd = vim.trim(cmd_output)
	trimmed_cmd = trimmed_cmd:gsub("^[%w._-]+ = ", "")

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
--- @return {old_path : string, new_path : string, is_rename : boolean}|nil A table with , or nil if parsing fails
function M.parse_file_info_from_status_line(line)
	if not line then
		return nil
	end

	line = vim.trim(line)

	-- Handle renamed files in nested path form:
	--   R dir/{old_name => new_name}
	local dir_path, old_name, new_name = line:match("^R%s+(.*)/{(.*)%s=>%s([^}]+)}$")
	if dir_path and old_name and new_name then
		return {
			old_path = dir_path .. "/" .. old_name,
			new_path = dir_path .. "/" .. new_name,
			is_rename = true,
		}
	end

	-- Handle renamed files in top-level brace form:
	--   R {old_name => new_name}
	local old_top, new_top = line:match("^R%s+{(.-)%s=>%s([^}]+)}$")
	if old_top and new_top then
		return {
			old_path = old_top,
			new_path = new_top,
			is_rename = true,
		}
	end

	-- Handle simple rename form:
	--   R old_path => new_path
	local old_path, new_path = line:match("^R%s+(.+)%s=>%s(.+)$")
	if old_path and new_path then
		return {
			old_path = vim.trim(old_path),
			new_path = vim.trim(new_path),
			is_rename = true,
		}
	end

	-- Regular status lines (M/A/D/?/!)
	local filepath = line:match("^[MAD?!]%s+(.+)$")
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
function M.get_revset(line)
	-- Build pattern to match graph characters and symbols at start of line
	-- Include: box-drawing chars, whitespace, jujutsu UTF-8 symbols, and ASCII markers
	local graph_chars = "│┃┆┇┊┋╭╮╰╯├┤┬┴┼─└┘┌┐%s" -- box-drawing + whitespace

	-- Jujutsu UTF-8 symbols (with their byte sequences)
	local utf8_symbols = {
		"\226\151\134", -- ◆ U+25C6 (diamond)
		"\226\151\139", -- ○ U+25CB (circle)
		"\195\151", -- × U+00D7 (conflict)
	}

	-- ASCII markers (escaped for pattern matching)
	-- Note: "/" is excluded because it's used as divergent change separator (e.g., rs/1)
	local ascii_markers = { "@", "%*", "\\", "%-", "%+", "|" }

	-- MUST have at least one commit marker symbol to be a valid commit line
	-- Otherwise it's a description/message line, not a commit marker line
	local has_marker_symbol = false

	-- Check for UTF-8 symbols
	for _, symbol in ipairs(utf8_symbols) do
		if line:find(symbol) then
			has_marker_symbol = true
			break
		end
	end

	-- Also check for ASCII markers (@ only) at start of line or after graph chars
	if not has_marker_symbol then
		-- Check for @ that appears early in the line
		if line:match("^[%s│┃┆┇┊┋╭╮╰╯├┤┬┴┼─└┘┌┐|\\]*[@]") then
			has_marker_symbol = true
		end
	end

	if not has_marker_symbol then
		return nil
	end

	-- Build character class for allowed prefix
	local allowed_prefix = "[" .. graph_chars
	for _, symbol in ipairs(utf8_symbols) do
		allowed_prefix = allowed_prefix .. symbol
	end
	for _, marker in ipairs(ascii_markers) do
		allowed_prefix = allowed_prefix .. marker
	end
	allowed_prefix = allowed_prefix .. "]+" -- close class, match one or more (not zero)

	-- Match first alphanumeric sequence after graph prefix
	-- Supports divergent changes: revset/0, revset/1, etc.
	-- Only match if it's followed by whitespace, slash (for divergent), or end of string

	-- Try matching with divergent suffix first: revset/N where N is a number
	local revset, divergent_num = line:match("^" .. allowed_prefix .. "(%w+)/(%d+)")
	if revset and divergent_num then
		return revset .. "/" .. divergent_num
	end

	-- Try regular match followed by whitespace
	revset = line:match("^" .. allowed_prefix .. "(%w+)%s")
	if not revset then
		-- Try matching at end of line without trailing whitespace
		revset = line:match("^" .. allowed_prefix .. "(%w+)$")
	end

	return revset
end

--- Given a string with N lines find all revsets in them
--- @param lines string[] An array of lines to parse
--- @return string[]|nil An array of revsets found, or nil if none found
function M.get_all_revsets(lines)
	local revsets = {}
	for _, line in pairs(lines) do
		local revset = M.get_revset(line)
		if revset then
			table.insert(revsets, revset)
		end
	end

	return #revsets > 0 and revsets or nil
end

--- Given an annotation line, parses and returns its components with positions
--- @param line string The annotation line to parse
--- @return table A table with {rev = {value = string|nil, pos = {start, end}|nil}, name = {value = string|nil, pos = {start, end}|nil}, date = {value = string|nil, pos = {start, end}|nil}}
function M.parse_annotation_line(line)
	local rev, name, date = line:match("^(%S+)%s*|%s*(.-)%s*|%s*(.+)$")

	local result = {
		rev = { value = rev },
		name = { value = name },
		date = { value = date },
	}

	if rev then
		local id_start, id_end = line:find("^(%S+)")
		result.rev.pos = { id_start, id_end }
	end

	if name then
		local name_start = line:find("|") + 2
		local name_end = line:find("|", name_start) - 2 -- Unsure about this one since it can have N whitespaces but we'll see
		result.name.pos = { name_start, name_end + 1 }
	end

	if date then
		local date_start, date_end = line:find("%d%d%d%d%-%d%d%-%d%d%s%d%d:%d%d:%d%d%s[%+%-]%d%d:%d%d")
		result.date.pos = { date_start, date_end }
	end

	return result
end

-- Given a range with the format "left..right", parse and return the two revisions
--- @param range_str string The range string to parse (e.g., "left..right")
--- @return {left: string, right: string}|nil A table
function M.parse_diff_range(range_str)
	if not range_str then
		return nil
	end

	local left, right = range_str:match("^(%S+)%.%.(%S+)$")
	if left and right then
		return { left = left, right = right }
	end

	return nil
end

--- Parse a `<rev>:<path>` argument as used by file commands.
--- With no colon, the whole input is treated as a revision with no file.
--- A trailing colon (`<rev>:`) is accepted and treated as no file path.
--- @param input string
--- @return {rev: string|nil, path: string|nil}|nil
function M.parse_file_module_input(input)
	if not input then
		return nil
	end

	input = vim.trim(input)
	if input == "" then
		return nil
	end

	local rev, file = input:match("^([^:]+):(.*)$")
	if rev then
		if file == "" then
			return { rev = rev, path = nil }
		end
		return { rev = rev, path = file }
	end
	if input:find(":", 1, true) then
		return nil
	end
	return { rev = input, path = nil }
end

return M
