local utils = require("jj.utils")
local runner = require("jj.core.runner")

--- @class jj.picker.snacks
local M = {}

local function get_snacks_opts(opts)
	if opts.snacks == true then
		return {}
	end
	return opts.snacks --[[@as table]]
end

local function preview_item_cmd(snacks, ctx, ft)
	if ctx.item and ctx.item.preview_cmd then
		snacks.picker.preview.cmd(ctx.item.preview_cmd, ctx, ft and { ft = ft } or {})
	end
end

local function format_text_item(item)
	if not item then
		return {}
	end

	return {
		{ item.text or "" },
	}
end

--- Displays the status files in a snacks picker
---@param opts  jj.picker.config
---@param files jj.picker.file[]
function M.status(opts, files)
	if not opts.snacks then
		return utils.notify("Snacks picker is `disabled`", vim.log.levels.INFO)
	end

	local snacks = require("snacks")
	local snacks_opts = get_snacks_opts(opts)

	local merged_opts = vim.tbl_deep_extend("force", snacks_opts, {
		source = "jj",
		items = files,
		title = "JJ Status",
		format = "git_status",
		actions = {
			open_and_diff = function(picker, item)
				picker:close()
				if item and item.file then
					vim.schedule(function()
						vim.cmd("edit " .. vim.fn.fnameescape(item.file))
						vim.cmd("Jdiff")
					end)
				end
			end,
		},
		win = {
			input = {
				keys = {
					["<C-d>"] = { "open_and_diff", mode = { "i", "n" } },
				},
			},
		},
		preview = function(ctx)
			preview_item_cmd(snacks, ctx, "git")
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
	local snacks_opts = get_snacks_opts(opts)

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

			local _, ok = runner.execute_command(
				string.format("jj edit %s --ignore-immutable", item.rev),
				string.format("could not edit revision '%s'", item.rev)
			)

			if ok then
				utils.reload_changed_file_buffers()
				utils.notify(string.format("Editing revision `%s`", item.rev), vim.log.levels.INFO)
			end
		end,
		preview = function(ctx)
			preview_item_cmd(snacks, ctx, "git")
		end,
	})

	snacks.picker.pick(merged_opts)
end

--- Picker to chose conlicted revisions and resolve them
---@param opts  jj.picker.config
---@param conflicts jj.picker.conflict[]
function M.conflict(opts, conflicts)
	if not opts.snacks then
		return utils.notify("Snacks picker is `disabled`", vim.log.levels.INFO)
	end

	local snacks = require("snacks")
	local snacks_opts = get_snacks_opts(opts)

	local function exit_func(rev)
		return function(exit_code)
			if exit_code == 0 then
				utils.notify(string.format("Successfully resolved `%s`", rev), vim.log.levels.INFO)
			end
		end
	end

	local merged_opts = vim.tbl_deep_extend("force", snacks_opts, {
		source = "jj",
		items = conflicts,
		title = "JJ Conflicts",
		format = format_text_item,
		actions = {
			resolve_conflict = function(picker, item)
				if not item or not item.rev then
					return
				end

				local strategies = require("jj.cmd").config.resolve_strategies or nil

				if strategies and #strategies > 1 then
					vim.ui.select(strategies, {
						prompt = "Select a strategy to resolve the conflict",
						format_item = function(choice)
							return choice.name
						end,
					}, function(choice)
						if not choice then
							return
						end

						picker:close()
						require("jj.cmd").resolve({
							rev = item.rev,
							args = choice.args,
							external = choice.external,
							on_exit = exit_func(item.rev),
						})
					end)
				elseif strategies and #strategies == 1 then
					local choice = strategies[1]
					picker:close()
					require("jj.cmd").resolve({
						rev = item.rev,
						args = choice.args,
						external = choice.external,
						on_exit = exit_func(item.rev),
					})
				else
					picker:close()
					require("jj.cmd.resolve").resolve({ rev = item.rev, on_exit = exit_func(item.rev) })
				end
			end,
		},
		win = {
			input = {
				keys = {
					["<C-r>"] = { "resolve_conflict", mode = { "i", "n" } },
				},
			},
		},
		confirm = function(picker, item)
			picker:close()

			if not item or not item.rev then
				return
			end

			require("jj.cmd.resolve").resolve({ rev = item.rev, on_exit = exit_func(item.rev) })
		end,
		preview = function(ctx)
			preview_item_cmd(snacks, ctx, "git")
		end,
	})

	snacks.picker.pick(merged_opts)
end

return M
