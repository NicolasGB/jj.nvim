local utils = require("jj.utils")

--- @class jj.picker.snacks
local M = {}

--- Displays the status files in a snacks picker
---@param opts  jj.picker.config
---@param files jj.picker.file[]
function M.status(opts, files)
	if not opts.snacks then
		return utils.notify("Snacks picker is `disabled`", vim.log.levels.INFO)
	end

	local snacks = require("snacks")

	local snacks_opts
	-- If its true we default to an empty table
	if opts.snacks == true then
		snacks_opts = {}
	else
		--- Otherwise we get the table from the config
		---@type table
		snacks_opts = opts.snacks
	end

	local merged_opts = vim.tbl_deep_extend("force", snacks_opts, {
		source = "jj",
		items = files,
		title = "JJ Status",
		preview = function(ctx)
			if ctx.item.file then
				snacks.picker.preview.cmd(ctx.item.diff_cmd, ctx, {})
			end
		end,
	})

	snacks.picker.pick(merged_opts)
end

local function format_jj_log(item, picker)
	local a = Snacks.picker.util.align
	local ret = {} ---@type snacks.picker.Highlight[]

	-- Add symbol (if available) and revision
	if item.symbol and item.symbol ~= "" then
		ret[#ret + 1] = { a(item.symbol, 1, { truncate = true }), "SnacksPickerGitMsg" }
	else
		ret[#ret + 1] = { "?", "SnacksPickerGitMsg" }
	end

	ret[#ret + 1] = { " " }

	local rev = item.rev or "unknown"
	-- INFO: This highlight is kind of a nice hack to avoid doing my own highlighs for the moment
	--- At some point i'll probably do mines
	ret[#ret + 1] = { a(rev, 4, { truncate = true }), "SnacksPickerGitBreaking" }
	if #rev >= 4 then
		ret[#ret + 1] = { " " }
	end

	if item.author then
		ret[#ret + 1] = { a(item.author, 8, { truncate = true }), "SnacksPcikerGitMsg" }
		if #item.author >= 8 then
			ret[#ret + 1] = { " " }
		end
	end

	if item.time then
		local year, month, day = item.time:match("(%d+)-(%d+)-(%d+)")
		local formatted = string.format("%s-%s-%s", year, day, month)
		ret[#ret + 1] = { a(formatted, 10), "SnacksPickerGitDate" }
		if #formatted >= 10 then
			ret[#ret + 1] = { " " }
		end
	end

	if item.commit_id then
		ret[#ret + 1] = { a(item.commit_id, 10, { truncate = true }), "SnacksPickerGitCommit" }
		if #item.commit_id >= 4 then
			ret[#ret + 1] = { " " }
		end
	end

	-- This comes from snacks git description formattedr
	local desc = item.description or ""
	local type, scope, breaking, body = desc:match("^(%S+)%s*(%(.-%))(!?):%s*(.*)$")

	if not type then
		type, breaking, body = desc:match("^(%S+)(!?):%s*(.*)$")
	end
	local msg_hl = "SnacksPickerGitMsg"
	if type and body then
		local dimmed = vim.tbl_contains({ "chore", "bot", "build", "ci", "style", "test" }, type)
		msg_hl = dimmed and "SnacksPickerDimmed" or "SnacksPickerGitMsg"
		ret[#ret + 1] = {
			type,
			breaking ~= "" and "SnacksPickerGitBreaking" or dimmed and "SnacksPickerBold" or "SnacksPickerGitType",
		}
		if scope and scope ~= "" then
			ret[#ret + 1] = { scope, "SnacksPickerGitScope" }
		end
		if breaking ~= "" then
			ret[#ret + 1] = { "!", "SnacksPickerGitBreaking" }
		end
		ret[#ret + 1] = { ":", "SnacksPickerDelim" }
		ret[#ret + 1] = { " " }
		desc = body
	end

	ret[#ret + 1] = { desc, msg_hl }
	return ret
end

---@param opts  jj.picker.config
---@param log_lines jj.picker.log_line[]
function M.file_log_history(opts, log_lines)
	if not opts.snacks then
		return utils.notify("Snacks picker is `disabled`", vim.log.levels.INFO)
	end

	local snacks = require("snacks")

	local snacks_opts
	-- If its true we default to an empty table
	if opts.snacks == true then
		snacks_opts = {}
	else
		--- Otherwise we get the table from the config
		---@type table
		snacks_opts = opts.snacks
	end

	local merged_opts = vim.tbl_deep_extend("force", snacks_opts, {
		source = "jj",
		items = log_lines,
		title = "JJ Log",
		format = format_jj_log,
		confirm = function(picker, item)
			picker:close()

			if not item or not item.rev then
				return
			end

			local _, ok = utils.execute_command(
				string.format("jj edit %s --ignore-immutable", item.rev),
				string.format("could not edit revision '%s'", item.rev)
			)

			if ok then
				utils.notify(string.format("Editing revision `%s`", item.rev), vim.log.levels.INFO)
			end
		end,
		preview = function(ctx)
			if ctx.item.rev and ctx.item.diff_cmd then
				snacks.picker.preview.cmd(ctx.item.diff_cmd, ctx, {})
			end
		end,
	})

	snacks.picker.pick(merged_opts)
end

return M
