--- @class jj.cmd.log
local M = {}

local utils = require("jj.utils")
local runner = require("jj.core.runner")
local parser = require("jj.core.parser")
local terminal = require("jj.ui.terminal")
local buffer = require("jj.core.buffer")
local diff = require("jj.diff")

local log_selected_hl_group = "JJLogSelectedHlGroup"
local log_selected_ns_id = vim.api.nvim_create_namespace(log_selected_hl_group)
local log_special_mode_target_hl_group = "JJLogSpecialModeTargetHlGroup"
local log_special_mode_target_ns_id = vim.api.nvim_create_namespace(log_special_mode_target_hl_group)
local special_mode_autocmd_id = nil

--- @class jj.cmd.log_opts
--- @field summary? boolean
--- @field reversed? boolean
--- @field no_graph? boolean
--- @field limit? uinteger
--- @field revisions? string
--- @field raw_flags? string[]

---@type jj.cmd.log_opts
local default_log_opts = { summary = false, reversed = false, no_graph = false, limit = nil, raw_flags = nil }

--- @param modes string|string[]
--- @return string[]
local function as_mode_list(modes)
	if type(modes) == "table" then
		return modes
	end
	return { modes }
end

--- @param lhs string
--- @param lhs_list string[]
--- @return boolean
local function has_longer_prefix(lhs, lhs_list)
	for _, other in ipairs(lhs_list) do
		if lhs ~= other and other:sub(1, #lhs) == lhs then
			return true
		end
	end
	return false
end

--- @param keymaps jj.core.buffer.keymap[]
--- @return jj.core.buffer.keymap[]
local function split_keymaps_by_mode(keymaps)
	local split_keymaps = {}

	for _, keymap in ipairs(keymaps) do
		local modes = keymap.modes or keymap.mode or "n"
		for _, mode in ipairs(as_mode_list(modes)) do
			local mode_keymap = vim.deepcopy(keymap)
			mode_keymap.modes = mode
			mode_keymap.mode = nil
			table.insert(split_keymaps, mode_keymap)
		end
	end

	return split_keymaps
end

--- Set nowait=true for per-mode keymaps that are not a prefix of another keymap in the same mode.
--- @param keymaps jj.core.buffer.keymap[]
--- @return jj.core.buffer.keymap[]
local function apply_nowait_to_unique_keymaps(keymaps)
	local split_keymaps = split_keymaps_by_mode(keymaps)
	local lhs_by_mode = {}

	for _, keymap in ipairs(split_keymaps) do
		local lhs = keymap.lhs
		local mode = keymap.modes or "n"
		lhs_by_mode[mode] = lhs_by_mode[mode] or {}
		table.insert(lhs_by_mode[mode], lhs)
	end

	for _, keymap in ipairs(split_keymaps) do
		local lhs = keymap.lhs
		local mode = keymap.modes
		if not has_longer_prefix(lhs, lhs_by_mode[mode]) then
			keymap.opts = vim.tbl_extend("force", keymap.opts or {}, { nowait = true })
		end
	end

	return split_keymaps
end

--- Init log highlight groups
function M.init_log_highlights()
	local cfg = require("jj").config.highlights.log
	if not cfg then
		return
	end

	vim.api.nvim_set_hl(0, log_selected_hl_group, cfg.selected)
	vim.api.nvim_set_hl(0, log_special_mode_target_hl_group, cfg.targeted)
end

--- Get the next revision line in the log buffer after the current cursor position.
--- @param pos integer? Optional line number to start searching from. If not provided, uses the current cursor line.
--- @return integer? The line number of the next revision, or nil if none found. 1-indexed.
local function get_next_revision_line(pos)
	local buf = terminal.state.buf or vim.api.nvim_get_current_buf()
	local total_lines = vim.api.nvim_buf_line_count(buf)

	-- Start scanning from the line after the current revision line
	local start = pos
	if not start then
		start = vim.api.nvim_win_get_cursor(0)[1] + 1 -- Add 1 to start looking  for the next rev and not the actual
	else
		start = start + 1
	end

	for line = start, total_lines do
		local content = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1]
		if parser.get_revset(content) then
			return line
		end
	end

	return nil
end

--- Get the previous revision line in the log buffer before the current cursor position.
--- @param pos integer? Optional line number to start searching from. If not provided, uses the current cursor line. 1-indexed.
--- @return integer? The line number of the previous revision, or nil if none found. 1-indexed.
local function get_prev_revision_line(pos)
	local buf = terminal.state.buf or vim.api.nvim_get_current_buf()
	local start = pos
	if not start then
		start = vim.api.nvim_win_get_cursor(0)[1]
		-- Remove the current line to start looking for the previous rev and not the actual if not on the first line to avoid out of bounds
		if start ~= 1 then
			start = start - 1
		end
	end

	for line = start, 1, -1 do
		local content = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1]
		if parser.get_revset(content) then
			return line
		end
	end

	return nil
end

--- Find the revision line under cursor, handling description lines
---@return integer The line number of the revision line under the cursor, or the previous line if the current line is a description.
---@return string|nil The revset of the revision line under the cursor, or nil if not found. 1-indexed.
local function get_revset_line()
	local buf = terminal.state.buf or vim.api.nvim_get_current_buf()
	local current_line_num = vim.api.nvim_win_get_cursor(0)[1]
	local line = vim.api.nvim_get_current_line()
	local revset_line = current_line_num

	if not parser.get_revset(line) and current_line_num > 0 then
		revset_line = get_prev_revision_line() or current_line_num
		line = vim.api.nvim_buf_get_lines(buf, revset_line - 1, revset_line, false)[1]
	end

	return revset_line, parser.get_revset(line)
end

--- Gets revset from current line or parent in case we're on a description.
--- @return string|nil The revset if found in either current line or previous line, nil otherwise
local function get_revset()
	local _, rev = get_revset_line()
	return rev
end

--- If a line is selected in visual mode, get the all the needed marks
--- from selected lines to highlight them during operations like rebase.
--- Otherwise, get the mark from the current line.
--- @return {line: uinteger, col: uinteger, end_line: uinteger, end_col: uinteger}[]|nil List of marks
local function get_highlight_marks()
	local marks = {}
	local mode = vim.fn.mode()
	local buf = terminal.state.buf
	if not buf then
		utils.notify("No open log buffer", vim.log.levels.ERROR)
		return
	end

	if mode == "v" or mode == "V" then
		-- Visual mode: get selected lines
		local _, selected_start_line, selected_end_line = utils.get_visual_selection(buf)

		-- Get the lines based on revision content
		local start_line = get_prev_revision_line(selected_start_line) or selected_start_line
		local end_line = get_next_revision_line(selected_end_line)
		if not end_line then
			end_line = vim.api.nvim_buf_line_count(buf)
		else
			end_line = end_line - 1 -- Remove 1 more to highlight until the line before the next revision line, which is the description line
		end

		local end_col = vim.api.nvim_buf_get_lines(buf, end_line - 1, end_line, false)[1]
		table.insert(marks, {
			line = start_line - 1, -- Remove 1 since 1-indexed
			col = 0,
			end_line = end_line - 1, -- Remove 1 since 1-indexed
			end_col = end_col and #end_col or 0, -- If end_col is nil, set it to 0
		})
	else
		--
		-- Normal mode: current or previous line
		local revset_line, rev = get_revset_line()
		if rev then
			-- Get the next line (description)
			local end_line = get_next_revision_line()
			if not end_line then
				-- If there is no next revision line, we highlight until the end of the buffer
				end_line = vim.api.nvim_buf_line_count(buf)
			else
				end_line = end_line - 1 -- We want to highlight until the line before the next revision line, which is the description line
			end

			-- If not the first line
			if revset_line >= 1 then
				revset_line = revset_line - 1 -- Remove 1 since 1-indexed
			end

			local end_line_length = vim.api.nvim_buf_get_lines(buf, end_line - 1, end_line, false)[1] or ""
			table.insert(marks, {
				line = revset_line,
				col = 0,
				end_line = end_line - 1, -- Remove 1 since 1-indexed
				end_col = #end_line_length,
			})
		end
	end

	return marks
end

--- Apply highlight to target revision
--- @param buf integer Buffer number
--- @param revset_line integer Line number of the revision to highlight (1-indexed)
--- @param hl_group string Highlight group to use
local function apply_target_highlight(buf, revset_line, hl_group)
	local end_line = get_next_revision_line()
	if not end_line then
		-- If the last line get the end
		end_line = vim.api.nvim_buf_line_count(buf)
	else
		end_line = end_line - 1 -- Remove 1 since 1-indexed
	end
	vim.api.nvim_buf_set_extmark(
		buf,
		log_special_mode_target_ns_id,
		revset_line - 1, -- Remove 1 since it's 1-indexed
		0,
		{ end_line = end_line, end_col = 0, hl_group = hl_group }
	)
end

--- Clear previous target highlight
local function clear_target_highlight(buf)
	vim.api.nvim_buf_clear_namespace(buf, log_special_mode_target_ns_id, 0, -1)
end

--- Update special mode target highlight on cursor movement
local function update_special_mode_target_highlight()
	local buf = terminal.state.buf
	if not buf then
		return
	end

	clear_target_highlight(buf)

	local revset_line, rev = get_revset_line()
	if not rev then
		return
	end

	-- Only highlight if rev is not in selection
	local selected_revsets = vim.b.jj_rebase_revsets or vim.b.jj_squash_revsets or vim.b.jj_duplicate_revsets

	local is_in_selection = selected_revsets and string.find(selected_revsets, rev, 1, true)
	if not is_in_selection then
		apply_target_highlight(buf, revset_line, log_special_mode_target_hl_group)
	end
end

--- Extracts the revsets from either the current line or the selected lines in visual mode
--- @return string|nil The revsets string or nil if none found
local function extract_revsets_from_terminal_buffer()
	local buf = terminal.state.buf
	if not buf then
		utils.notify("No open log buffer", vim.log.levels.ERROR)
		return nil
	end

	local revsets_str = nil
	local mode = vim.fn.mode()

	-- Get revsets based on mode
	if mode == "n" then
		revsets_str = get_revset()
	elseif mode == "v" or mode == "V" then
		local start_line = vim.fn.line("v")
		local end_line = vim.fn.line(".")
		if start_line > end_line then
			start_line, end_line = end_line, start_line
		end

		-- Check if the start line has a revset if not we fetch until the previous rev
		if not parser.get_revset(vim.api.nvim_buf_get_lines(buf, start_line - 1, start_line, false)[1]) then
			start_line = get_prev_revision_line(start_line) or 1
		end

		local lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
		local revsets = parser.get_all_revsets(lines)
		if not revsets or #revsets == 0 then
			utils.notify("No valid revisions found in selected lines", vim.log.levels.ERROR)
			return nil
		end

		revsets_str = table.concat(revsets, " | ")
		-- Exit visual mode after extracting revsets
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
	else
		return nil
	end

	return revsets_str
end

--- Setup highlights for selected revisions in the log buffer
local function setup_selected_highlights()
	local buf = terminal.state.buf
	if not buf then
		return
	end

	-- Set highlights
	local marks = get_highlight_marks()
	if not marks or #marks == 0 then
		utils.notify("No valid revisions found to highlight", vim.log.levels.ERROR)
		return
	end

	for _, mark in ipairs(marks) do
		vim.api.nvim_buf_set_extmark(
			buf,
			log_selected_ns_id,
			mark.line,
			mark.col,
			{ end_line = mark.end_line, end_col = mark.end_col, hl_group = log_selected_hl_group }
		)
	end
end

--- Build the jj log command string from options
--- @param opts? jj.cmd.log_opts Optional command options
--- @return string[] The full jj log command
function M.build_log_cmd(opts)
	local jj_cmd = {
		"jj",
		"log",
		"--no-pager",
	}
	local merged_opts = vim.tbl_extend("force", default_log_opts, opts or {})

	if merged_opts.raw_flags then
		for _, flag in ipairs(merged_opts.raw_flags) do
			-- Strip --no-pager from raw_flags since it's already in the base command
			if flag ~= "--no-pager" then
				table.insert(jj_cmd, flag)
			end
		end
		return jj_cmd
	end

	if merged_opts.summary then
		table.insert(jj_cmd, "--summary")
	end
	if merged_opts.reversed then
		table.insert(jj_cmd, "--reversed")
	end
	if merged_opts.no_graph then
		table.insert(jj_cmd, "--no-graph")
	end
	if merged_opts.limit then
		vim.list_extend(jj_cmd, { "--limit", tostring(merged_opts.limit) })
	end
	if merged_opts.revisions then
		vim.list_extend(jj_cmd, { "--revisions", merged_opts.revisions })
	end

	return jj_cmd
end

--- Jujutsu log
--- @param opts? jj.cmd.log_opts Optional command options
function M.log(opts)
	if not utils.ensure_jj() then
		return
	end

	-- If a log was already being displayed before this command we will want to maintain the cursor position
	if terminal.is_log_buffer_open() then
		terminal.store_cursor_position()
		-- Make sure to clear highlights before rerunning since the previous log buffer might have some
		vim.api.nvim_buf_clear_namespace(terminal.state.buf, log_selected_ns_id, 0, -1)
		vim.api.nvim_buf_clear_namespace(terminal.state.buf, log_special_mode_target_ns_id, 0, -1)
	end

	terminal.run(M.build_log_cmd(opts), M.log_keymaps())
end

---
--- Create a new change relative to the revision under the cursor in a jj log buffer.
--- Behavior:
---   flag == nil       -> branch off the current revision
---   flag == "after"   -> create a new change after the current revision (-A)
--- If ignore_immut is true, adds --ignore-immutable to the command.
--- Silently returns if no revision is found or the jj command fails.
--- On success, notifies and refreshes the log buffer.
--- @param flag? 'after' Position relative to the current revision; nil to branch off.
--- @param ignore_immut? boolean Pass --ignore-immutable to jj when true.
function M.handle_log_new(flag, ignore_immut)
	local revsets = extract_revsets_from_terminal_buffer()
	if not revsets then
		return
	end

	-- Delete the pipes from the revsets string since jj new expects space separated revsets
	revsets = revsets:gsub("| ", "")

	local is_multiple = revsets:find(" ") ~= nil

	-- Mapping for flag-specific options and messages.
	local flag_map = {
		after = {
			opt = "-A",
			err = "Error creating new change after: `%s`",
			ok = is_multiple and "Successfully created merge change after: `%s`"
				or "Successfully created change after: `%s`",
		},
		default = {
			opt = "",
			err = "Error creating new change branching off `%s`",
			ok = is_multiple and "Successfully created merge change from: `%s`"
				or "Successfully created change branching off `%s`",
		},
	}

	local cfg = flag_map[flag] or flag_map.default

	-- Build command parts
	local cmd = { "jj", "new" }
	if cfg.opt ~= "" then
		-- For -A flag, each revset needs its own -A prefix
		for rev in revsets:gmatch("%S+") do
			table.insert(cmd, cfg.opt)
			table.insert(cmd, rev)
		end
	else
		-- Revsets should always be inserted 1 by one
		for rev in revsets:gmatch("%S+") do
			table.insert(cmd, rev)
		end
	end
	if ignore_immut then
		table.insert(cmd, "--ignore-immutable")
	end

	runner.execute_async(cmd, function()
		utils.notify(string.format(cfg.ok, revsets), vim.log.levels.INFO)
		-- Refresh the log buffer after creating the change.
		M.log()
	end, string.format(cfg.err, revsets))
end

--- Handle diffing a log line
function M.handle_log_diff()
	local revsets = extract_revsets_from_terminal_buffer()
	if not revsets then
		utils.notify("No valid revision found in the log line", vim.log.levels.ERROR)
		return
	end

	-- Delete the pipes from the revsets string since jj new expects space separated revsets
	revsets = revsets:gsub("| ", "")

	local is_multiple = revsets:find(" ") ~= nil

	if not is_multiple then
		diff.show_revision({ rev = revsets })
	else
		-- Get the first and the last revset to diff
		local list = vim.split(revsets, "%s+", { trimempty = true })
		diff.diff_revisions({ left = list[1], right = list[#list] })
	end
end

--- Handle log history
function M.handle_log_history()
	local revsets = extract_revsets_from_terminal_buffer()
	if not revsets then
		utils.notify("No valid revision found in the log line", vim.log.levels.ERROR)
		return
	end

	-- Delete the pipes from the revsets string since jj new expects space separated revsets
	revsets = revsets:gsub("| ", "")

	local is_multiple = revsets:find(" ") ~= nil

	if is_multiple then
		-- Get the first and the last revset to diff
		local list = vim.split(revsets, "%s+", { trimempty = true })
		diff.diff_history_revisions({ left = list[1], right = list[#list] })
	end
end

--- Handle describing a log line
function M.handle_log_describe()
	-- Store the cursor pos for when we exit the describe
	terminal.store_cursor_position()
	local revset = get_revset()
	if revset then
		require("jj.cmd").describe(nil, revset, nil, function()
			-- Execute log
			M.log()
			-- Restore previous cursor pos
			terminal.restore_cursor_position()
		end)
	else
		utils.notify("No valid revision found in the log line", vim.log.levels.ERROR)
	end
end

--- Handle keypress edit on `jj log` buffer to edit a revision.
--- If ignore_immut is true, adds --ignore-immutable to the command.
--- Silently returns if no revision is found or the jj command fails.
--- On success, notifies and refreshes the log buffer.
--- @param ignore_immut? boolean Pass --ignore-immutable to jj edit when true.
--- @param close_on_exit? boolean Close the log buffer after editing when true.
function M.handle_log_edit(ignore_immut, close_on_exit)
	local revset = get_revset()
	if not revset or revset == "" then
		return
	end

	-- If we found a revision, edit it.

	-- Build command parts.
	local cmd = { "jj", "edit" }
	if ignore_immut then
		table.insert(cmd, "--ignore-immutable")
	end

	table.insert(cmd, revset)

	-- Try to execute cmd
	runner.execute_async(cmd, function()
		utils.reload_changed_file_buffers()

		-- Close the terminal buffer
		if close_on_exit then
			utils.notify(string.format("Editing change: `%s`", revset), vim.log.levels.INFO)
			terminal.close_terminal_buffer()
		else
			M.log({})
		end
	end, "Error editing change")
end

--- Handle abandon `jj log` buffer.
--- If ignore_immut is true, adds --ignore-immutable to the command.
--- Silently returns if no revision is found or the jj command fails.
--- On success, notifies and refreshes the log buffer.
--- @param ignore_immut? boolean Pass --ignore-immutable to jj abandon when true.
function M.handle_log_abandon(ignore_immut)
	local revsets = extract_revsets_from_terminal_buffer()
	if not revsets then
		return
	end

	-- Delete the pipes from the revsets string since jj abandon expects space separated revsets
	revsets = revsets:gsub("| ", "")

	-- If we found revision(s), abandon it.

	-- Build command parts.
	local cmd = { "jj", "abandon" }
	if ignore_immut then
		table.insert(cmd, "--ignore-immutable")
	end

	table.insert(cmd, revsets)

	-- Try to execute cmd
	runner.execute_async(cmd, function()
		local text = "Abandoned change: `%s`"
		if revsets:find(" ", 1) then
			text = "Abandoned changes: `%s`"
		end
		utils.notify(string.format(text, revsets), vim.log.levels.INFO)
		M.log({})
	end, "Error abandoning change")
end

--- Handle fetching from `jj log` buffer.
function M.handle_log_fetch()
	local remotes = utils.get_remotes()
	if not remotes or #remotes == 0 then
		utils.notify("No git remotes found to fetch from", vim.log.levels.ERROR)
		return
	end

	if #remotes > 1 then
		-- Prompt to select a remote
		vim.ui.select(remotes, {
			prompt = "Select remote to fetch from: ",
			format_item = function(item)
				return string.format("%s (%s)", item.name, item.url)
			end,
		}, function(choice)
			if choice then
				local cmd = { "jj", "git", "fetch", "--remote", choice.name }
				runner.execute_async(cmd, function()
					utils.notify(string.format("Fetching from %s...", choice), vim.log.levels.INFO)
					M.log({})
				end, "Error fetching from remote")
			end
		end)
	else
		-- Only one remote, fetch from it directly
		local cmd = { "jj", "git", "fetch" }
		utils.notify("Fetching from remote...", vim.log.levels.INFO)
		runner.execute_async(cmd, function()
			utils.notify("Successfully fetched from remote", vim.log.levels.INFO)
			M.log({})
		end, "Error fetching from remote")
	end
end

--- Handle pushing from `jj log` buffer.
--- Ask the user which local bookmark to push.
function M.handle_log_push_from_all()
	local bookmarks = utils.get_all_bookmarks_with_status()
	local cmd = { "jj", "git", "push" }
	if not bookmarks or #bookmarks == 0 then
		utils.notify("No bookmarks found to push", vim.log.levels.ERROR)
		return
	end

	vim.ui.select(bookmarks, {
		prompt = "Select bookmark to push: ",
		format_item = function(item)
			if item.is_deleted then
				return item.name .. " (deleted)"
			end
			return item.name
		end,
	}, function(choice)
		if choice then
			-- Add the bookmark name to the command
			vim.list_extend(cmd, { "-b", choice.name })

			utils.notify(string.format("Pushing bookmark `%s`...", choice.name), vim.log.levels.INFO)
			runner.execute_async(cmd, function(output)
				if output and string.find(output, "Nothing changed%.") then
					utils.notify("Nothing changed.", vim.log.levels.INFO)
				else
					utils.notify(string.format("Successfully pushed bookmark `%s`", choice.name), vim.log.levels.INFO)
					M.log({})
				end
			end, string.format("Error pushing bookmark `%s`", choice.name))
		else
			return
		end
	end)
end

--- Handle log pushing bookmark from current line in `jj log` buffer.
function M.handle_log_push_bookmark()
	local revset = get_revset()
	if not revset or revset == "" then
		return
	end

	local bookmarks = utils.get_bookmarks_for_rev(revset)
	if not bookmarks or #bookmarks == 0 then
		utils.notify("No bookmark found for revision", vim.log.levels.ERROR)
		return
	end

	-- Function to push the bookmark, takes the full command as argument
	--- @param cmd string[] The command to execute
	local function push(cmd)
		runner.execute_async(cmd, function(output)
			if output and string.find(output, "Nothing changed%.") then
				utils.notify("Nothing changed.", vim.log.levels.INFO)
			else
				utils.notify(string.format("Successfully pushed bookmark for `%s`", revset), vim.log.levels.INFO)
				M.log({})
			end
		end, string.format("Error pushing bookmark for `%s`", revset))
	end

	-- If there are multiple bookmarks user must choose
	if #bookmarks > 1 then
		table.insert(bookmarks, { name = "[All]", is_deleted = false })

		vim.ui.select(bookmarks, {
			prompt = "Which bookmark do you want to push?",
			format_item = function(item)
				if item.is_deleted then
					return item.name .. " (deleted)"
				end
				return item.name
			end,
		}, function(choice)
			if choice then
				local cmd = { "jj", "git", "push" }
				if choice.name == "[All]" then
					-- Push all bookmarks
					table.insert(cmd, "--all")
					utils.notify("Pushing `ALL` bookmarks", vim.log.levels.INFO)
				else
					vim.list_extend(cmd, { "-b", choice.name })
					utils.notify(string.format("Pushing bookmark `%s`...", choice.name), vim.log.levels.INFO)
				end
				push(cmd)
			else
				return
			end
		end)
	else
		-- If there's only one bookmark simply push it
		local b = bookmarks[1].name
		local cmd = { "jj", "git", "push", "-b", b }
		utils.notify(string.format("Pushing bookmark `%s`...", b), vim.log.levels.INFO)
		push(cmd)
	end
end

--- Handle seting a tag from `jj log` buffer for the revision under cursor
--- @param revset? string Revset to set the tag on, if not provided it will do nothing.
function M.handle_log_tag_set(revset)
	if not revset or revset == "" then
		revset = revset or get_revset()
		if not revset or revset == "" then
			return
		end
	end

	require("jj.cmd").tag_set(revset)
end

--- Handle log change revset
function M.handle_log_change_revset()
	vim.ui.input({ prompt = "Enter new revset: " }, function(input)
		if input and input ~= "" then
			M.log({ revisions = input })
		end
	end)
end

--- Handle opening a PR/MR from `jj log` buffer for the revision under cursor
--- @param list_bookmarks? boolean If true, prompt to select from all bookmarks instead of using current revision
function M.handle_log_open_pr(list_bookmarks)
	if list_bookmarks then
		-- Get all bookmarks
		local bookmarks = utils.get_all_bookmarks()

		if #bookmarks == 0 then
			utils.notify("No bookmarks found", vim.log.levels.ERROR)
			return
		end

		-- Prompt to select a bookmark
		vim.ui.select(bookmarks, {
			prompt = "Select bookmark to open PR for: ",
		}, function(choice)
			if choice then
				utils.open_pr_for_bookmark(choice)
			end
		end)
		-- Return early
		return
	end

	-- Default behavior: parse revision and open PR
	local revset = get_revset()
	if not revset or revset == "" then
		return
	end

	-- Get the bookmark for this revision
	local bookmarks = utils.get_bookmarks_for_rev(revset)
	if not bookmarks or #bookmarks == 0 then
		utils.notify("[OPEN PR] No bookmark found for revision", vim.log.levels.ERROR)
		return
	end

	if #bookmarks > 1 then
		vim.ui.select(bookmarks, {
			prompt = "Which bookmark do you want to open PR for?",
			format_item = function(item)
				if item.is_deleted then
					return item.name .. " (deleted)"
				end
				return item.name
			end,
		}, function(choice)
			if choice then
				utils.open_pr_for_bookmark(choice.name)
			end
		end)
	else
		-- Open the PR using the utility function
		utils.open_pr_for_bookmark(bookmarks[1].name)
	end
end

function M.handle_log_bookmark_del()
	local revset = get_revset()
	if not revset or revset == "" then
		return
	end

	local curr_bookmarks = utils.get_bookmarks_for_rev(revset)
	if not curr_bookmarks or #curr_bookmarks == 0 then
		utils.notify("No bookmark found for revision", vim.log.levels.ERROR)
		return
	end

	---@param b_names string[] Bookmark names to delete
	local function delete_bookmarks(b_names)
		local cmd = { "jj", "bookmark", "delete" }
		for _, b in ipairs(b_names) do
			table.insert(cmd, b)
		end
		local b_str = table.concat(b_names, " ")
		runner.execute_async(cmd, function()
			utils.notify(string.format("Deleted bookmark `%s`", b_str), vim.log.levels.INFO)
			M.log({})
		end, string.format("Error deleting bookmark `%s`", b_str))
	end

	table.insert(curr_bookmarks, { name = "[All]", is_deleted = false })

	vim.ui.select(curr_bookmarks, {
		prompt = "Which bookmark do you want to delete?",
		format_item = function(item)
			if item.is_deleted then
				return item.name .. " (deleted)"
			end
			return item.name
		end,
	}, function(choice)
		if choice then
			if choice.name == "[All]" then
				local all_names = vim.iter(curr_bookmarks)
					:filter(function(b)
						return b.name ~= "[All]"
					end)
					:map(function(b)
						return b.name
					end)
					:totable()
				delete_bookmarks(all_names)
			else
				delete_bookmarks({ choice.name })
			end
		end
	end)
end

-- Create or move bookmark at revision under cursor in `jj log` buffer
function M.handle_log_bookmark()
	local revset = get_revset()
	if not revset or revset == "" then
		return
	end

	-- Get all bookmarks
	local bookmarks = utils.get_all_bookmarks()
	table.insert(bookmarks, 1, "[Create new]")
	-- Prompt to select or create a bookmark
	vim.ui.select(bookmarks, {
		prompt = "Select a bookmark to move or create a new: ",
	}, function(choice)
		if choice then
			if choice == "[Create new]" then
				local prefix = require("jj.cmd").config.bookmark.prefix or ""
				-- Prompt for new bookmark name
				vim.ui.input({ prompt = "Enter new bookmark name: ", default = prefix }, function(input)
					if input and input ~= "" then
						local cmd = { "jj", "bookmark", "create", input, "-r", revset }
						runner.execute_async(cmd, function()
							utils.notify(
								string.format("Created bookmark `%s` at `%s`", input, revset),
								vim.log.levels.INFO
							)
							M.log({})
						end, "Error creating bookmark")
					end
				end)
			else
				-- Move existing bookmark to the revision
				local cmd = { "jj", "bookmark", "move", choice, "--to", revset, "-B" }
				runner.execute_async(cmd, function()
					utils.notify(string.format("Moved bookmark `%s` to `%s`", choice, revset), vim.log.levels.INFO)
					M.log({})
				end, "Error moving bookmark")
			end
		end
	end)
end

--- Rebase bookmark(s)
function M.handle_log_rebase()
	local revsets_str = extract_revsets_from_terminal_buffer()
	-- Validate revsets
	if not revsets_str or revsets_str == "" then
		return
	end
	vim.b.jj_rebase_revsets = revsets_str

	-- Set highlights
	setup_selected_highlights()

	M.transition_mode("rebase")
	utils.notify("Rebase `started`.", vim.log.levels.INFO, 500)
end

--- Squash bookmarks(s)
function M.handle_log_squash()
	local revsets_str = extract_revsets_from_terminal_buffer()
	-- Validate revsets
	if not revsets_str or revsets_str == "" then
		return
	end

	vim.b.jj_squash_revsets = revsets_str
	-- Set highlights
	setup_selected_highlights()

	M.transition_mode("squash")
	utils.notify("Squash `started`.", vim.log.levels.INFO, 500)
end

--- Duplicate bookmark(s)
function M.handle_log_duplicate()
	local revsets_str = extract_revsets_from_terminal_buffer()
	-- Validate revsets
	if not revsets_str or revsets_str == "" then
		return
	end
	vim.b.jj_duplicate_revsets = revsets_str

	-- Set highlights
	setup_selected_highlights()

	M.transition_mode("duplicate")
	utils.notify("Duplication `started`.", vim.log.levels.INFO, 500)
end

--- Quick squash the bookmark under the cursor into it's parent
function M.handle_log_quick_squash()
	local revset = get_revset()
	if not revset or revset == "" then
		return
	end

	local cmd = { "jj", "squash", "-r", revset, "-u", "--ignore-immutable" }
	utils.notify(string.format("Squashing `%s` into it's parent...", revset), vim.log.levels.INFO)
	runner.execute_async(cmd, function()
		utils.notify(string.format("Successfully squashed `%s` into it's parent", revset), vim.log.levels.INFO)
		M.log({})
	end, string.format("Error squashing `%s` into it's parent", revset))
end

--- Handle log split
function M.handle_log_split()
	local revset = get_revset()
	if not revset or revset == "" then
		return
	end

	require("jj.cmd").split({
		rev = revset,
		on_exit = function(exit_code)
			if exit_code == 0 then
				utils.notify(string.format("Successfully split `%s`", revset), vim.log.levels.INFO)
				vim.schedule(function()
					M.log({})
				end)
			else
				utils.notify(string.format("Cancelled splitting `%s`", revset), vim.log.levels.WARN)
				-- Since we previously replaced the floating with the split we actually want to re run the log cmd
				if require("jj").config.terminal.window.type == "floating" then
					vim.schedule(function()
						M.log({})
					end)
				end
			end
		end,
	})
end

--- Handle log resolve conflict
function M.handle_log_resolve()
	local revset = get_revset()
	if not revset or revset == "" then
		return
	end

	if not utils.is_change_conflicted(revset) then
		utils.notify(string.format("Revision `%s` has no conflicts to resolve", revset), vim.log.levels.INFO)
		return
	end

	local exit_func = function(exit_code)
		if exit_code == 0 then
			utils.notify(string.format("Successfully resolved `%s`", revset), vim.log.levels.INFO)
			vim.schedule(function()
				M.log({})
			end)
		else
			-- Since we previously replaced the floating with the resolve we actually want to re run the log cmd
			if require("jj").config.terminal.window.type == "floating" then
				vim.schedule(function()
					M.log({})
				end)
			end
		end
	end

	local strategies = require("jj.cmd").config.resolve_strategies
	if strategies and #strategies > 1 then
		vim.ui.select(strategies, {
			prompt = "Select a resolve strategy: ",
			format_item = function(item)
				return item.name
			end,
		}, function(choice)
			if choice then
				require("jj.cmd").resolve({
					rev = revset,
					args = choice.args,
					external = choice.external,
					on_exit = exit_func,
				})
			end
		end)
	elseif strategies and #strategies == 1 then
		local choice = strategies[1]
		require("jj.cmd").resolve({ rev = revset, args = choice.args, external = choice.external, on_exit = exit_func })
	else
		-- Simply resolve with the default
		require("jj.cmd").resolve({ rev = revset, on_exit = exit_func })
	end
end

--- Handle diff action in summary tooltip
--- Diffs the file at revset against its parent (revset-)
--- Opens a floating diff, and returns focus to tooltip when closed
--- @param revset string The revision being viewed
function M.handle_summary_diff(revset)
	local line = vim.api.nvim_get_current_line()
	local filepath = parser.parse_file_info_from_status_line(line)
	if not filepath then
		utils.notify("No file found on this line", vim.log.levels.WARN)
		return
	end

	-- Keep the tooltip open
	if terminal.state.tooltip_buf and vim.api.nvim_buf_is_valid(terminal.state.tooltip_buf) then
		terminal.keep_tooltip_open(true)
	end

	-- Use the diff module to show what changed in this revision for this file
	diff.show_revision({
		rev = revset,
		path = filepath.new_path,
	})
end

--- Handle edit action in summary tooltip (opens file after jj edit)
--- Closes tooltip and log buffer, edits the revision, and opens the file
--- @param revset string The revision to edit
--- @param ignore_immut boolean Whether to ignore immutability
function M.handle_summary_edit(revset, ignore_immut)
	-- Before anything check if the revset is immutable and the ignore_immut flag is set
	if utils.is_change_immutable(revset) and not ignore_immut then
		utils.notify(
			string.format("The change `%s` is immutable, use the `edit_immutable` shortcut.", revset),
			vim.log.levels.WARN
		)
		return
	end

	local line = vim.api.nvim_get_current_line()
	local filepath = parser.parse_file_info_from_status_line(line)
	if not filepath then
		utils.notify("No file found on this line", vim.log.levels.WARN)
		return
	end

	-- Close the tooltip first
	if terminal.state.tooltip_buf and vim.api.nvim_buf_is_valid(terminal.state.tooltip_buf) then
		terminal.close_tooltip()
	end

	-- Close the log buffer
	terminal.close_terminal_buffer()

	local cmd = { "jj", "edit", revset }
	if ignore_immut then
		table.insert(cmd, "--ignore-immutable")
	end

	runner.execute_async(cmd, function()
		utils.reload_changed_file_buffers()
		utils.notify(string.format("Editing revset: `%s`", revset), vim.log.levels.INFO)
		-- Open the file in the current window
		vim.cmd("edit " .. vim.fn.fnameescape(filepath.new_path))
	end, string.format("Error editing revset: `%s`", revset))
end

--- Handle edit action in summary tooltip but only for the file (like Jedit)
--- Closes tooltip, edits the revision, and opens the file
--- @param revset string The revision to edit
function M.handle_summary_file_edit(revset)
	local line = vim.api.nvim_get_current_line()
	local filepath = parser.parse_file_info_from_status_line(line)
	if not filepath then
		utils.notify("No file found on this line", vim.log.levels.WARN)
		return
	end

	-- Close the tooltip first
	if terminal.state.tooltip_buf and vim.api.nvim_buf_is_valid(terminal.state.tooltip_buf) then
		terminal.close_tooltip()
	end

	require("jj.file").open_target({ path = filepath.new_path, rev = revset, split = "tab" })
end

--- Get keymaps for summary tooltip
--- @param revset string The revision being viewed
--- @return jj.core.buffer.keymap[]
function M.summary_keymaps(revset)
	local cmd = require("jj.cmd")
	local keymaps = cmd.config.keymaps.log.summary_tooltip or {}
	local specs = {
		diff = {
			modes = { "n" },
			handler = M.handle_summary_diff,
			args = { revset },
			desc = "Diff file at this revision",
		},
		edit = {
			modes = { "n" },
			handler = M.handle_summary_edit,
			args = { revset, false },
			desc = "Edit revision and open file",
		},
		edit_immutable = {
			modes = { "n" },
			handler = M.handle_summary_edit,
			args = { revset, true },
			opts = { desc = "Edit revision (ignore immutability) and open file" },
		},
		edit_file = {
			modes = { "n" },
			handler = M.handle_summary_file_edit,
			args = { revset, true },
			opts = { desc = "Read revision in buffer like `Jedit`" },
		},
	}
	return cmd.resolve_keymaps_from_specs(keymaps, specs)
end

--- Build the summary command for a revset
--- @param revset string The revision to show summary for
--- @return string[] The jj log command
local function build_summary_cmd(revset)
	local template = '"Commit ID: " ++ commit_id ++ "\\n" '
		.. '++ "Change ID: " ++ change_id ++ "\\n" '
		.. '++ "Author: " ++ author ++ " (" ++ author.timestamp() ++ ")\\n" '
		.. '++ "Committer: " ++ committer ++ " (" ++ committer.timestamp() ++ ")\\n\\n" '
		.. "++ description "
		.. '++ "\\n" ++ self.diff().summary()'

	return {
		"jj",
		"log",
		"-r",
		revset,
		"--no-graph",
		"-T",
		template,
	}
end

--- Handle showing summary tooltip for revision under cursor
--- First K shows tooltip without entering, second K enters the tooltip
function M.handle_log_summary()
	-- If tooltip exists and is valid, enter it on second K
	if terminal.state.tooltip_buf and vim.api.nvim_buf_is_valid(terminal.state.tooltip_buf) then
		local revset = vim.b[terminal.state.tooltip_buf].jj_summary_revset
		if revset and terminal.state.tooltip_buf and vim.api.nvim_win_is_valid(terminal.state.tooltip_win) then
			-- Store the cursor position
			terminal.store_cursor_position()
			-- Enter the tooltip window and set up keymaps
			vim.api.nvim_set_current_win(terminal.state.tooltip_win)
			buffer.set_keymaps(terminal.state.tooltip_buf, M.summary_keymaps(revset))
			return
		end
	end

	local revset = get_revset()
	if not revset or revset == "" then
		return
	end

	local cmd = build_summary_cmd(revset)

	-- Run command synchronously first to calculate dimensions
	local output, success = runner.execute(cmd, nil, nil, false)
	if not success or not output then
		return
	end

	-- Calculate dimensions based on output
	local lines = vim.split(output, "\n", { trimempty = false })
	local max_width = 0
	for _, line in ipairs(lines) do
		max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
	end
	local width = math.min(max_width + 2, vim.o.columns - 4)
	local height = #lines

	local buf, _ = terminal.run_tooltip(cmd, {
		title = string.format(" Summary: %s ", revset),
		enter = false,
		width = width,
		height = height,
	})

	if buf then
		vim.b[terminal.state.tooltip_buf].jj_summary_revset = revset
	end
end

--- Move cursor to the next or previous revision line in the log buffer.
--- @param direction integer 1 for next, -1 for previous
local function select_revision(direction)
	local target_line
	if direction == 1 then
		target_line = get_next_revision_line()
	elseif direction == -1 then
		target_line = get_prev_revision_line()
	else
		return
	end

	if target_line then
		vim.api.nvim_win_set_cursor(0, { target_line, 0 })
	end
end

--- Move cursor to the next revision in the log buffer
function M.handle_log_select_next_revision()
	select_revision(1)
end

--- Move cursor to the previous revision in the log buffer
function M.handle_log_select_prev_revision()
	select_revision(-1)
end

--- Resolve log keymaps from config, filtering out nil values
--- @return jj.core.buffer.keymap[]
function M.log_keymaps()
	local cmd = require("jj.cmd")

	-- Reduce repetition by declaring a specification table.
	-- Each entry maps the config key name to:
	--   desc: Keybind description
	--   handler: function to call
	--   args: optional list of arguments passed to handler
	local keymaps = cmd.config.keymaps.log or {}
	local close_on_edit = cmd.config.log.close_on_edit or false

	--- @type jj.cmd.keymap_specs
	local specs = {
		edit = {
			desc = "Checkout revision under cursor",
			handler = M.handle_log_edit,
			args = { false, close_on_edit },
			modes = { "n" },
		},
		edit_immutable = {
			desc = "Checkout revision under cursor (ignores immutability)",
			handler = M.handle_log_edit,
			args = { true, close_on_edit },
			modes = { "n" },
		},
		describe = {
			desc = "Describe revision under cursor",
			handler = M.handle_log_describe,
			modes = { "n" },
		},
		diff = {
			desc = "Diff revision under cursor",
			handler = M.handle_log_diff,
			modes = { "n", "v" },
		},
		new = {
			desc = "Create new change branching off revision under cursor",
			handler = M.handle_log_new,
			args = { nil, false },
			modes = { "n", "v" },
		},
		new_after = {
			desc = "Create new change after revision under cursor",
			handler = M.handle_log_new,
			args = { "after", false },
			modes = { "n", "v" },
		},
		new_after_immutable = {
			desc = "Create new change after revision under cursor (ignores immutability)",
			handler = M.handle_log_new,
			args = { "after", true },
			modes = { "n", "v" },
		},
		undo = {
			desc = "Undo last change",
			handler = cmd.undo,
			modes = { "n" },
		},
		redo = {
			desc = "Redo last undone change",
			handler = cmd.redo,
			modes = { "n" },
		},
		abandon = {
			desc = "Abandon revision under cursor",
			handler = M.handle_log_abandon,
			-- As of now i'm only exposing the non ignore-immutable version of abandon in the keymaps
			-- Maybe in the future we can add another keymap for that, if people request it
			args = { false },
			modes = { "n", "v" },
		},
		fetch = {
			desc = "Fetch from remote",
			handler = M.handle_log_fetch,
			modes = { "n" },
		},
		push_all = {
			desc = "Push one of the local bookmarks to remote",
			handler = M.handle_log_push_from_all,
			modes = { "n" },
		},
		push = {
			desc = "Push bookmark of revision under cursor to remote",
			handler = M.handle_log_push_bookmark,
			modes = { "n" },
		},
		open_pr = {
			desc = "Open PR/MR for revision under cursor",
			handler = M.handle_log_open_pr,
			modes = { "n" },
		},
		open_pr_list = {
			desc = "Open PR/MR by selecting from all bookmarks",
			handler = M.handle_log_open_pr,
			args = { true },
			modes = { "n" },
		},
		bookmark = {
			desc = "Create or move bookmark at revision under cursor",
			handler = M.handle_log_bookmark,
			modes = { "n" },
		},
		bookmark_del = {
			desc = "Delete bookmark at revision under cursor",
			handler = M.handle_log_bookmark_del,
			modes = { "n" },
		},
		rebase = {
			desc = "Rebase bookmark(s)",
			handler = M.handle_log_rebase,
			modes = { "n", "v" },
		},
		squash = {
			desc = "Squash bookmark(s)",
			handler = M.handle_log_squash,
			modes = { "n", "v" },
		},
		duplicate = {
			desc = "Duplicate bookmark(s)",
			handler = M.handle_log_duplicate,
			modes = { "n", "v" },
		},
		quick_squash = {
			desc = "Squash the bookmark under the cursor into it's parent (-r) keeping parent's message (-u), alwas ignores immutability",
			handler = M.handle_log_quick_squash,
			modes = { "n" },
		},
		summary = {
			desc = "Show summary tooltip for revision under cursor",
			handler = M.handle_log_summary,
			modes = { "n" },
		},
		split = {
			desc = "Split the revision under cursor",
			handler = M.handle_log_split,
			modes = { "n" },
		},
		tag_set = {
			desc = "Set a tag under the current revset",
			handler = M.handle_log_tag_set,
			modes = { "n" },
		},
		history = {
			desc = "Show history diff between revisions (only works with multiple revsets selected)",
			handler = M.handle_log_history,
			modes = { "v" },
		},
		change_revset = {
			desc = "Change the revset(s) being viewed",
			handler = M.handle_log_change_revset,
			modes = { "n", "v" },
		},
		select_next_revision = {
			desc = "Move cursor to the next revision",
			handler = M.handle_log_select_next_revision,
			modes = { "n", "v" },
		},
		select_prev_revision = {
			desc = "Move cursor to the previous revision",
			handler = M.handle_log_select_prev_revision,
			modes = { "n", "v" },
		},
		resolve = {
			desc = "Resolve conflicts for revision under cursor",
			handler = M.handle_log_resolve,
			modes = { "n" },
		},
	}

	local merged_keymaps = cmd.merge_keymaps(cmd.resolve_keymaps_from_specs(keymaps, specs), cmd.terminal_keymaps())
	return apply_nowait_to_unique_keymaps(merged_keymaps)
end

--- Rebase mode keymaps
--- @return jj.core.buffer.keymap[]
function M.rebase_keymaps()
	local cmd = require("jj.cmd")
	local keymaps = cmd.config.keymaps.log.rebase_mode or {}

	--- @type jj.cmd.keymap_specs
	local spec = {
		onto = {
			desc = "Rebase onto (-O) the revision under cursor",
			handler = M.handle_rebase_execute,
			args = { "onto" },
			modes = { "n" },
		},
		after = {
			desc = "Rebase revset(s) after (-A) the revision under cursor",
			handler = M.handle_rebase_execute,
			args = { "after" },
			modes = { "n" },
		},
		before = {
			desc = "Rebase revset(s) before (-B) the revision under cursor",
			handler = M.handle_rebase_execute,
			args = { "before" },
			modes = { "n" },
		},
		onto_immutable = {
			desc = "Rebase onto (-O) the revision under cursor (ignores immutability)",
			handler = M.handle_rebase_execute,
			args = { "onto", true },
			modes = { "n" },
		},
		after_immutable = {
			desc = "Rebase revset(s) after (-A) the revision under cursor (ignores immutability)",
			handler = M.handle_rebase_execute,
			args = { "after", true },
			modes = { "n" },
		},
		before_immutable = {
			desc = "Rebase revset(s) before (-B) the revision under cursor (ignores immutability)",
			handler = M.handle_rebase_execute,
			args = { "before", true },
			modes = { "n" },
		},
		exit_mode = {
			desc = "Exit rebase to normal mode",
			handler = M.handle_special_mode_exit,
			args = { "Rebase" },
			modes = { "n" },
		},
	}

	return apply_nowait_to_unique_keymaps(cmd.resolve_keymaps_from_specs(keymaps, spec))
end

--- Squash mode keymaps
--- @return jj.core.buffer.keymap[]
function M.squash_keymaps()
	local cmd = require("jj.cmd")
	local keymaps = cmd.config.keymaps.log.squash_mode or {}

	--- @type jj.cmd.keymap_specs
	local spec = {
		into = {
			desc = "Squash into (-t) the revision under cursor",
			handler = M.handle_squash_execute,
			args = { "into" },
			modes = { "n" },
		},
		into_immutable = {
			desc = "Squash onto (-i) the revision under cursor (ignores immutability)",
			handler = M.handle_squash_execute,
			args = { "into", true },
			modes = { "n" },
		},
		exit_mode = {
			desc = "Exit squash to normal mode",
			handler = M.handle_special_mode_exit,
			args = { "Squash" },
			modes = { "n" },
		},
	}

	return apply_nowait_to_unique_keymaps(cmd.resolve_keymaps_from_specs(keymaps, spec))
end

--- Duplicate mode keymaps
--- @return jj.core.buffer.keymap[]

function M.duplicate_keymaps()
	local cmd = require("jj.cmd")
	local keymaps = cmd.config.keymaps.log.duplicate_mode or {}

	--- @type jj.cmd.keymap_specs
	local spec = {
		onto = {
			desc = "Duplicate onto (-O) the revision under cursor",
			handler = M.handle_duplicate_execute,
			args = { "onto" },
			modes = { "n" },
		},
		after = {
			desc = "Duplicate revset(s) after (-A) the revision under cursor",
			handler = M.handle_duplicate_execute,
			args = { "after" },
			modes = { "n" },
		},
		before = {
			desc = "Duplicate revset(s) before (-B) the revision under cursor",
			handler = M.handle_duplicate_execute,
			args = { "before" },
			modes = { "n" },
		},
		onto_immutable = {
			desc = "Duplicate onto (-O) the revision under cursor (ignores immutability)",
			handler = M.handle_duplicate_execute,
			args = { "onto", true },
			modes = { "n" },
		},
		after_immutable = {
			desc = "Duplicate revset(s) after (-A) the revision under cursor (ignores immutability)",
			handler = M.handle_duplicate_execute,
			args = { "after", true },
			modes = { "n" },
		},
		before_immutable = {
			desc = "Duplicate revset(s) before (-B) the revision under cursor (ignores immutability)",
			handler = M.handle_duplicate_execute,
			args = { "before", true },
			modes = { "n" },
		},
		exit_mode = {
			desc = "Exit normal to normal mode",
			handler = M.handle_special_mode_exit,
			args = { "Duplication" },
			modes = { "n" },
		},
	}

	return apply_nowait_to_unique_keymaps(cmd.resolve_keymaps_from_specs(keymaps, spec))
end

--- Get keymaps for a specific mode
--- @param mode string Mode name
--- @return jj.core.buffer.keymap[]
function M.get_keymaps_for_mode(mode)
	if mode == "normal" then
		return M.log_keymaps()
	elseif mode == "rebase" then
		return M.rebase_keymaps()
	elseif mode == "squash" then
		return M.squash_keymaps()
	elseif mode == "duplicate" then
		return M.duplicate_keymaps()
	end
	return {}
end

--- Transition between buffer modes by swapping keymaps
--- @param target_mode "normal"|"rebase"|"squash"|"duplicate" Target mode name (e.g., "normal", "rebase")
function M.transition_mode(target_mode)
	-- Get the mode keymaps
	if target_mode == vim.b.jj_mode then
		return
	end

	-- Get new keymaps for target mode
	local new_keymaps = M.get_keymaps_for_mode(target_mode)
	terminal.replace_terminal_keymaps(new_keymaps)

	-- Set up or tear down special mode autocmd
	if target_mode ~= "normal" then
		special_mode_autocmd_id = vim.api.nvim_create_autocmd("CursorMoved", {
			buffer = terminal.state.buf,
			callback = update_special_mode_target_highlight,
		})
		-- Highlight initial position
		update_special_mode_target_highlight()
	elseif special_mode_autocmd_id then
		vim.api.nvim_del_autocmd(special_mode_autocmd_id)
		special_mode_autocmd_id = nil
		-- Clear target highlight
		local buf = terminal.state.buf or 0
		vim.api.nvim_buf_clear_namespace(buf, log_special_mode_target_ns_id, 0, -1)
	end

	-- Update buffer mode state
	vim.b.jj_mode = target_mode
end

--- Handle special mode exit
--- @param mode "Rebase"|"Squash"|"Duplicate" The mode that is being exited, used for notification message
function M.handle_special_mode_exit(mode)
	-- Clear stored revsets
	vim.b.jj_rebase_revsets = nil
	vim.b.jj_squash_revsets = nil
	vim.b.jj_duplicate_revsets = nil

	M.transition_mode("normal")
	-- Clear highlights
	local buf = terminal.state.buf or 0
	vim.api.nvim_buf_clear_namespace(buf, log_selected_ns_id, 0, -1)
	vim.api.nvim_buf_clear_namespace(buf, log_special_mode_target_ns_id, 0, -1)

	utils.notify(string.format("%s `canceled`", mode), vim.log.levels.INFO, 500)
end

--- Handle rebase execution with mode
--- @param mode "onto" | "after" | "before" Rebase mode
--- @param ignore_immut boolean? Wether or not to ignore immutability
function M.handle_rebase_execute(mode, ignore_immut)
	-- Get all revsets in the format "xx xy xz"
	local revsets = vim.b.jj_rebase_revsets
	local destination_revset = get_revset()
	if not destination_revset or destination_revset == "" then
		return
	end

	local mode_flat = "-o"
	if mode == "after" then
		mode_flat = "-A"
	elseif mode == "before" then
		mode_flat = "-B"
	end

	utils.notify(string.format("Rebasing...", revsets, mode, destination_revset), vim.log.levels.INFO, 500)
	local cmd = {
		"jj",
		"rebase",
		"-r",
		revsets,
		mode_flat,
		destination_revset,
	}

	-- If ignore_immut is true, add the flag
	-- This is not currently exposed in keymaps but could be in the future
	if ignore_immut then
		table.insert(cmd, "--ignore-immutable")
	end

	runner.execute_async(cmd, function()
		utils.notify(
			string.format("Rebased `%s` %s `%s` successfully", revsets, mode, destination_revset),
			vim.log.levels.INFO
		)
		vim.b.jj_rebase_revsets = nil

		-- Clear all highlighting before transitioning
		local buf = terminal.state.buf or 0
		vim.api.nvim_buf_clear_namespace(buf, log_selected_ns_id, 0, -1)
		vim.api.nvim_buf_clear_namespace(buf, log_special_mode_target_ns_id, 0, -1)

		M.transition_mode("normal")
		-- Refresh log
		M.log({})
	end, "Error during rebase.")
end

--- Handle squash execution
--- @param mode "into" Squash mode
--- @param ignore_immut boolean? Wether or not to ignore immutability
function M.handle_squash_execute(mode, ignore_immut)
	-- Get all revsets in the format "xx xy xz"
	local revsets = vim.b.jj_squash_revsets
	local destination_revset = get_revset()
	if not destination_revset or destination_revset == "" then
		return
	end

	utils.notify(string.format("Squashing...", revsets, mode, destination_revset), vim.log.levels.INFO, 500)
	-- U flag to keep destination's message
	local cmd = { "jj", "squash", "-f", revsets, "-u" }

	if mode == "into" then
		vim.list_extend(cmd, { "-t", destination_revset })
	end

	-- If ignore_immut is true, add the flag
	-- This is not currently exposed in keymaps but could be in the future
	if ignore_immut then
		table.insert(cmd, "--ignore-immutable")
	end

	runner.execute_async(cmd, function()
		utils.notify(
			string.format("Squashed `%s` into `%s` successfully", revsets, destination_revset),
			vim.log.levels.INFO
		)
		vim.b.jj_squash_revsets = nil

		-- Clear all highlighting before transitioning
		local buf = terminal.state.buf or 0
		vim.api.nvim_buf_clear_namespace(buf, log_selected_ns_id, 0, -1)
		vim.api.nvim_buf_clear_namespace(buf, log_special_mode_target_ns_id, 0, -1)

		M.transition_mode("normal")
		-- Refresh log
		M.log({})
	end, "Error during squashing.")
end

-- Handle duplicate execution
--- @param mode "onto" | "after" | "before" Rebase mode
--- @param ignore_immut boolean? Wether or not to ignore immutability
function M.handle_duplicate_execute(mode, ignore_immut)
	-- Get all revsets in the format "xx xy xz"
	local revsets = vim.b.jj_duplicate_revsets
	local destination_revset = get_revset()
	if not destination_revset or destination_revset == "" then
		return
	end

	local mode_flat = "-o"
	if mode == "after" then
		mode_flat = "-A"
	elseif mode == "before" then
		mode_flat = "-B"
	end

	utils.notify(string.format("Duplicating...", revsets, mode, destination_revset), vim.log.levels.INFO, 500)
	local cmd = { "jj", "duplicate", revsets, mode_flat, destination_revset }

	-- If ignore_immut is true, add the flag
	-- This is not currently exposed in keymaps but could be in the future
	if ignore_immut then
		table.insert(cmd, "--ignore-immutable")
	end

	runner.execute_async(cmd, function()
		utils.notify(
			string.format("Duplicated `%s` %s `%s` successfully", revsets, mode, destination_revset),
			vim.log.levels.INFO
		)
		vim.b.jj_duplicate_revsets = nil

		-- Clear all highlighting before transitioning
		local buf = terminal.state.buf or 0
		vim.api.nvim_buf_clear_namespace(buf, log_selected_ns_id, 0, -1)
		vim.api.nvim_buf_clear_namespace(buf, log_special_mode_target_ns_id, 0, -1)

		M.transition_mode("normal")
		-- Refresh log
		M.log({})
	end, "Error during duplication.")
end

return M
