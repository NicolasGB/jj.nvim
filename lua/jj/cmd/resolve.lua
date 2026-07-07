local M = {}

local utils = require("jj.utils")
local jj_args = require("jj.core.args")
local terminal = require("jj.ui.terminal")
local runner = require("jj.core.runner")

--- Resolve conflicts in the current change.
--- @param opts? jj.cmd.resolve.opts
function M.resolve(opts)
	opts = vim.tbl_deep_extend("force", {}, opts or {}) --[[@as jj.cmd.resolve.opts]]
	local rev = opts.rev or "@"
	local filesets = opts.filesets or {}
	local args = opts.args or {}

	if not utils.ensure_jj() then
		return
	end

	local cmd = { "jj", "resolve", "--revision", rev }
	-- Extra arguments
	vim.list_extend(cmd, args)

	-- Append filesets as jj string literal
	for _, fileset in ipairs(filesets) do
		table.insert(cmd, jj_args.fileset(fileset))
	end

	utils.notify(string.format("Resolving conflicts in change `%s`...", rev), vim.log.levels.INFO)

	-- If external is set, run the command asynchronously and invoke the on_exit callback if provided
	if opts.external then
		-- Run the command asynchronously and notify the user of the result
		runner.execute_async(
			cmd,
			function(output)
				if output and output ~= "" then
					utils.notify(output, vim.log.levels.INFO)
				end
				if opts.on_exit then
					opts.on_exit(0)
				end
			end,
			string.format("Could not resolve conflicts in `%s`", rev),
			nil,
			nil,
			function()
				if opts.on_exit then
					opts.on_exit(1)
				end
			end
		)
	else
		-- Otherwise, run in a floating terminal
		terminal.run_floating(cmd, nil, {
			title = " JJ Resolve ",
			modifiable = true,
			keep_modifiable = true,
			interactive = true,
			on_exit = opts.on_exit or nil,
		})
	end
end

return M
