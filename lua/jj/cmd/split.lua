local M = {}

local utils = require("jj.utils")
local terminal = require("jj.ui.terminal")

--- Clamps a ratio value between 0.1 and 1.0, returning a default of 1.0 if the input is invalid.
---@param value? number
---@param field string
---@return number
local function clamp_ratio(value, field)
	if type(value) ~= "number" or value < 0.1 or value > 1.0 then
		utils.notify(
			string.format("Value for field `%s` must be between `0.1` and `1.0`. Defaulted to `1.0`", field),
			vim.log.levels.WARN
		)
		return 1.0
	end
	return value
end

local function build_split_command(opts)
	local args = { "jj", "split" }

	local rev = (opts.rev and opts.rev ~= "") and opts.rev or "@"
	table.insert(args, "-r")
	table.insert(args, rev)

	if opts.parallel then
		table.insert(args, "--parallel")
	end

	if opts.message then
		table.insert(args, "--message")
		table.insert(args, opts.message)
	end

	if opts.ignore_immutable then
		table.insert(args, "--ignore-immutable")
	end

	if opts.filesets then
		for _, fileset in ipairs(opts.filesets) do
			table.insert(args, fileset)
		end
	end

	return table.concat(args, " ")
end

--- Split natively
---@param opts? jj.cmd.split.opts
function M.split(opts)
	if not utils.ensure_jj() then
		return
	end

	local cmd_mod = require("jj.cmd")
	opts = vim.tbl_deep_extend("force", cmd_mod.config.split or {}, opts or {}) --[[@as jj.cmd.split.opts]]
	opts.height = clamp_ratio(opts.height, "height")
	opts.width = clamp_ratio(opts.width, "width")

	-- If it's empty do nothing
	if utils.is_change_empty(opts.rev or "@") then
		utils.notify(string.format("The change `%s` is empty, nothing to split.", opts.rev or "@"), vim.log.levels.INFO)
		return
	end

	local function run_split(cmd)
		terminal.run_floating(cmd, nil, {
			title = " JJ Split ",
			modifiable = true,
			height = math.floor(vim.o.lines * opts.height),
			width = math.floor(vim.o.columns * opts.width),
			keep_modifiable = true,
			interactive = true,
			on_exit = opts.on_exit or nil,
		})
	end

	-- If the change is immutable warn the user and prompt him
	if utils.is_change_immutable(opts.rev or "@") then
		vim.ui.select(
			{ "Yes", "No" },
			{ prompt = string.format("The change `%s` is IMMUTABLE, do you still want to split it?", opts.rev or "@") },
			function(item)
				if item == "Yes" then
					opts.ignore_immutable = true
					local cmd = build_split_command(opts)
					run_split(cmd)
					return
				end
			end
		)
	else
		local cmd = build_split_command(opts)
		run_split(cmd)
	end
end

return M
