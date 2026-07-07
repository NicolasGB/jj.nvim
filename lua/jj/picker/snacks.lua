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

--- Append git-style highlighted description segments to a Snacks highlight array.
---
--- If the description matches a conventional-commit-like shape such as
--- `feat(scope)!: body`, this splits and highlights the type/scope/breaking
--- marker separately, then appends the remaining body with `default_hl`.
--- Otherwise the whole description is appended as a single segment.
---
--- @param ret snacks.picker.Highlight[]
--- @param desc string|nil
--- @param default_hl? string Highlight group used for the description body/fallback text
local function append_description_hl(ret, desc, default_hl)
	desc = desc or ""

	local type, scope, breaking, body = desc:match("^(%S+)%s*(%(.-%))(!?):%s*(.*)$")
	if not type then
		type, breaking, body = desc:match("^(%S+)(!?):%s*(.*)$")
	end

	local msg_hl = default_hl or "SnacksPickerGitMsg"
	if type and body then
		local dimmed = vim.tbl_contains({ "chore", "bot", "build", "ci", "style", "test" }, type)
		msg_hl = dimmed and "SnacksPickerDimmed" or (default_hl or "SnacksPickerGitMsg")
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
end

--- Format a conflict picker entry with git-like colored segments.
---
--- Layout:
--- - change/revision id
--- - author
--- - first-line description
---
--- @param item jj.picker.conflict|nil
--- @return snacks.picker.Highlight[]
local function format_conflict_item(item)
	if not item then
		return {}
	end

	local a = Snacks.picker.util.align
	local ret = {} ---@type snacks.picker.Highlight[]

	ret[#ret + 1] = { a(item.rev or "unknown", 12, { truncate = true }), "Constant" }
	ret[#ret + 1] = { " " }
	ret[#ret + 1] = { a(item.author or "(no author)", 16, { truncate = true }), "Identifier" }
	ret[#ret + 1] = { " " }
	append_description_hl(ret, item.description, "Comment")

	return ret
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
			if ctx.item and ctx.item.diff_cmd then
				snacks.picker.preview.cmd(ctx.item.diff_cmd, ctx, {})
			end
		end,
	})

	snacks.picker.pick(merged_opts)
end

local function format_jj_log(item)
	local a = Snacks.picker.util.align
	local ret = {} ---@type snacks.picker.Highlight[]

	local rev = item.rev or "unknown"
	ret[#ret + 1] = { a(rev, 12, { truncate = true }), "SnacksPickerGitBreaking" }
	ret[#ret + 1] = { " " }

	local author = item.author or "(no author)"
	ret[#ret + 1] = { a(author, 16, { truncate = true }), "Identifier" }
	ret[#ret + 1] = { " " }

	local formatted_time = item.time and (item.time:match("^%d%d%d%d%-%d%d%-%d%d") or item.time) or ""
	ret[#ret + 1] = { a(formatted_time, 10, { truncate = true }), "SnacksPickerGitDate" }
	ret[#ret + 1] = { " " }

	append_description_hl(ret, item.description)
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

			local _, ok = runner.execute(
				{ "jj", "edit", item.rev, "--ignore-immutable" },
				string.format("could not edit revision '%s'", item.rev)
			)

			if ok then
				utils.reload_changed_file_buffers()
				utils.notify(string.format("Editing revision `%s`", item.rev), vim.log.levels.INFO)
			end
		end,
		preview = function(ctx)
			if ctx.item and ctx.item.preview_cmd then
				snacks.picker.preview.cmd(ctx.item.preview_cmd, ctx, { ft = "git" })
			end
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

	local picker = require("jj.picker")

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
		format = format_conflict_item,
		actions = {
			edit_revision = function(snacks_picker, item)
				snacks_picker:close()

				if not item or not item.rev then
					return
				end

				local _, ok = runner.execute(
					{ "jj", "edit", item.rev, "--ignore-immutable" },
					string.format("could not edit revision '%s'", item.rev)
				)

				if ok then
					utils.reload_changed_file_buffers()
					utils.notify(string.format("Editing conflicted revision `%s`", item.rev), vim.log.levels.INFO)
				end
			end,
		},
		win = {
			input = {
				keys = {
					["<C-e>"] = { "edit_revision", mode = { "i", "n" } },
				},
			},
		},
		confirm = function(snacks_picker, item)
			snacks_picker:close()
			picker.resolve_conflict(item, exit_func(item and item.rev or ""))
		end,
		preview = function(ctx)
			if ctx.item and ctx.item.preview_cmd then
				snacks.picker.preview.cmd(ctx.item.preview_cmd, ctx, { ft = "git" })
			end
		end,
	})

	snacks.picker.pick(merged_opts)
end

--- Format a conflict-section picker entry as `<relative file path>:<line>`,
--- the line being where the conflict's opening marker is.
---
--- @param item jj.picker.conflict_section|nil
--- @return snacks.picker.Highlight[]
local function format_conflict_section_item(item)
	if not item then
		return {}
	end

	local ret = {} ---@type snacks.picker.Highlight[]

	ret[#ret + 1] = { item.rel_path or item.file or "", "SnacksPickerFile" }
	ret[#ret + 1] = { ":" .. tostring(item.pos and item.pos[1] or 0), "SnacksPickerRow" }

	return ret
end

--- Picker to navigate to each individual conflict section in the current revision.
---
--- The items are a standard file source (`file` + `pos`), so the default Snacks
--- bindings apply: `<CR>` opens in the current window, `<C-s>` in a split,
--- `<C-v>` in a vertical split and `<C-t>` in a new tab, with a live file
--- preview positioned on the conflict marker.
---@param opts jj.picker.config
---@param sections jj.picker.conflict_section[]
function M.conflict_sections(opts, sections)
	if not opts.snacks then
		return utils.notify("Snacks picker is `disabled`", vim.log.levels.INFO)
	end

	local snacks = require("snacks")
	local snacks_opts = get_snacks_opts(opts)

	local merged_opts = vim.tbl_deep_extend("force", snacks_opts, {
		source = "jj",
		items = sections,
		title = "JJ Conflicts",
		format = format_conflict_section_item,
	})

	snacks.picker.pick(merged_opts)
end

return M
