local M = {}

local utils = require("jj.utils")
local terminal = require("jj.ui.terminal")
local runner = require("jj.core.runner")

---@class jj.resolve.opts
---@field rev string|nil The revision to resolve, defaults to "@"
---@field filesets string[]|nil The filesets to resolve, defaults to all filesets
---@field external boolean|nil Whether to use external merge tool, if this boolean is set the command will not be ran in a floating terminal inside neovim (defaults: false)
---@field args string[]|nil Additional arguments to pass to the resolve command

--- Resolve conflicts in the current change.
--- @param opts? jj.resolve.opts
function M.resolve(opts)
	opts = vim.tbl_deep_extend("force", {}, opts or {}) --[[@as jj.resolve.opts]]
	local rev = opts.rev or "@"
	local filesets = opts.filesets or {}
	local args = opts.args or {}

	if not utils.ensure_jj() then
		return
	end

	local cmd_args = { "jj", "resolve", "--revision", rev }
	-- Extra arguments
	vim.list_extend(cmd_args, args)
	-- Append the filestes
	vim.list_extend(cmd_args, filesets)

	utils.notify(string.format("Resolving conflicts in change `%s`...", rev), vim.log.levels.INFO)

	-- If external is set, run the command asynchronously and invoke the on_exit callback if provided
	if opts.external then
		-- Run the command asynchronously and notify the user of the result
		runner.execute_command_async(table.concat(cmd_args, " "), function(output)
			if output and output ~= "" then
				utils.notify(output, vim.log.levels.INFO)
			end
		end, string.format("Could not resolve conflicts in `%s`", rev))
	else
		-- Otherwise, run in a floating terminal
		terminal.run_floating(table.concat(cmd_args, " "), nil, {
			title = " JJ Resolve ",
			modifiable = true,
			keep_modifiable = true,
			interactive = true,
		})
	end
end

return M
