local M = {}

--- Build a jj fileset string literal for a path.
--- jj path arguments use fileset syntax, so special characters like `$`
--- must be wrapped in jj string quotes.
---@param path string
---@return string
function M.fileset(path)
	return string.format('"%s"', path:gsub("\\", "\\\\"):gsub('"', '\\"'))
end

return M
