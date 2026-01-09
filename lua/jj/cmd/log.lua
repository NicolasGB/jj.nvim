--- @class jj.cmd.log
local M = {}

local utils = require("jj.utils")
local runner = require("jj.core.runner")
local parser = require("jj.core.parser")
local terminal = require("jj.ui.terminal")

local log_selected_hl_group = "JJLogSelectedHlGroup"
local log_selected_ns_id = vim.api.nvim_create_namespace(log_selected_hl_group)
local log_special_mode_target_hl_group = "JJLogSpecialModeTargetHlGroup"
local log_special_mode_target_ns_id = vim.api.nvim_create_namespace(log_special_mode_target_hl_group)
local rebase_mode_autocmd_id = nil
local last_rebase_target_line = nil
local HIGHLIGHT_RANGE = 2 -- Revision line + description line

--- @class jj.cmd.log_opts
--- @field summary? boolean
--- @field reversed? boolean
--- @field no_graph? boolean
--- @field limit? uinteger
--- @field revisions? string
--- @field raw_flags? string

---@type jj.cmd.log_opts
local default_log_opts = { summary = false, reversed = false, no_graph = false, limit = 20, raw_flags = nil }

--- Init log highlight groups
function M.init_log_highlights()
	local cfg = require("jj").config.highlights.log
	if not cfg then
		return
	end

	vim.api.nvim_set_hl(0, log_selected_hl_group, cfg.selected)
	vim.api.nvim_set_hl(0, log_special_mode_target_hl_group, cfg.targeted)
end

--- Find the revision line under cursor, handling description lines
local function get_revset_line()
	local buf = terminal.state.buf or vim.api.nvim_get_current_buf()
	local current_line_num = vim.api.nvim_win_get_cursor(0)[1] - 1
	local line = vim.api.nvim_get_current_line()
	local revset_line = current_line_num

	if not parser.get_revset(line) and current_line_num > 0 then
		revset_line = current_line_num - 1
		line = vim.api.nvim_buf_get_lines(buf, revset_line, revset_line + 1, false)[1]
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
		local start_line = vim.fn.line("v")
		local end_line = vim.fn.line(".")
		if start_line > end_line then
			start_line, end_line = end_line, start_line
		end

		local lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
		for i, line in ipairs(lines) do
			-- If the current line has a revset highlight it with the following one (which is the description)
			if parser.get_revset(line) then
				-- Compute the actual line number
				local mark_lstart = start_line + i - 2 -- marks expect 0 api since, start-line and ipars are both 1 indexed we need to remove 2 to transform to 0-index (For future self)
				local mark_lend = start_line + i - 1 -- We highlight start + description so we actually want to stop at the next line included
				local next_line = lines[i + 1] -- Get the next line contents
				if not next_line then
					-- Only fetch if it's the last selected line and has a revset
					local next_line_num = start_line + i
					next_line = vim.api.nvim_buf_get_lines(buf, next_line_num - 1, next_line_num, false)[1] or ""
				end

				table.insert(marks, {
					line = mark_lstart,
					col = 0, -- Maybe at some  point will make the parser say where the data starts but one thing at the time
					end_line = mark_lend,
					end_col = #next_line,
				})
			end
		end
	else
		--
		-- Normal mode: current or previous line
		local revset_line, rev = get_revset_line()
		if rev then
			-- Get the next line (description)
			local next_line = vim.api.nvim_buf_get_lines(buf, revset_line + 1, revset_line + 2, false)[1] or ""
			table.insert(marks, {
				line = revset_line,
				col = 0,
				end_line = revset_line + 1,
				end_col = #next_line,
			})
		end
	end

	return marks
end

--- Apply highlight to target revision
local function apply_target_highlight(buf, revset_line, hl_group)
	vim.api.nvim_buf_set_extmark(
		buf,
		log_special_mode_target_ns_id,
		revset_line,
		0,
		{ end_line = revset_line + HIGHLIGHT_RANGE, end_col = 0, hl_group = hl_group }
	)
	last_rebase_target_line = revset_line
end

--- Clear previous target highlight
local function clear_target_highlight(buf)
	if last_rebase_target_line ~= nil then
		vim.api.nvim_buf_clear_namespace(
			buf,
			log_special_mode_target_ns_id,
			last_rebase_target_line,
			last_rebase_target_line + HIGHLIGHT_RANGE
		)
	end
	last_rebase_target_line = nil
end

--- Update rebase target highlight on cursor movement
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
	local is_in_selection = vim.b.jj_rebase_revsets and string.find(vim.b.jj_rebase_revsets, rev, 1, true)
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

--- Jujutsu log
--- @param opts? jj.cmd.log_opts Optional command options
function M.log(opts)
	if not utils.ensure_jj() then
		return
	end

	-- If a log was already being displayed before this command we will want to maintain the cursor position
	if terminal.state.buf_cmd == "log" then
		terminal.store_cursor_position()
		-- Make sure to clear highlights before rerunning since the previous log buffer might have some
		vim.api.nvim_buf_clear_namespace(terminal.state.buf, log_selected_ns_id, 0, -1)
		vim.api.nvim_buf_clear_namespace(terminal.state.buf, log_special_mode_target_ns_id, 0, -1)
	end

	local jj_cmd = "jj log"
	local merged_opts = vim.tbl_extend("force", default_log_opts, opts or {})

	-- If a raw has been given simply execute it as is
	if merged_opts.raw_flags then
		return terminal.run(string.format("%s %s", jj_cmd, merged_opts.raw_flags), M.log_keymaps())
	end

	for key, value in pairs(merged_opts) do
		key = key:gsub("_", "-")
		if key == "limit" and value then
			jj_cmd = string.format("%s --%s %d", jj_cmd, key, value)
		elseif key == "revisions" and value then
			jj_cmd = string.format("%s --%s %s", jj_cmd, key, value)
		elseif value then
			jj_cmd = string.format("%s --%s", jj_cmd, key)
		end
	end

	terminal.run(jj_cmd, M.log_keymaps())
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
	local cmd_parts = { "jj", "new" }
	if cfg.opt ~= "" then
		-- For -A flag, each revset needs its own -A prefix
		for rev in revsets:gmatch("%S+") do
			table.insert(cmd_parts, cfg.opt)
			table.insert(cmd_parts, rev)
		end
	else
		table.insert(cmd_parts, revsets)
	end
	if ignore_immut then
		table.insert(cmd_parts, "--ignore-immutable")
	end

	local cmd = table.concat(cmd_parts, " ")
	runner.execute_command_async(cmd, function()
		utils.notify(string.format(cfg.ok, revsets), vim.log.levels.INFO)
		-- Refresh the log buffer after creating the change.
		require("jj.cmd").log()
	end, string.format(cfg.err, revsets))
end

--- Handle diffing a log line
function M.handle_log_diff()
	local revset = get_revset()

	if revset then
		local cmd = string.format("jj show --no-pager %s", revset)
		terminal.run_floating(cmd, require("jj.cmd").floating_keymaps())
	else
		utils.notify("No valid revision found in the log line", vim.log.levels.ERROR)
	end
end

--- Handle describing a log line
function M.handle_log_describe()
	local revset = get_revset()
	if revset then
		require("jj.cmd").describe(nil, revset)
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
	local cmd_parts = { "jj", "edit" }
	if ignore_immut then
		table.insert(cmd_parts, "--ignore-immutable")
	end

	table.insert(cmd_parts, revset)

	-- Build cmd string
	local cmd = table.concat(cmd_parts, " ")

	-- Try to execute cmd
	runner.execute_command_async(cmd, function()
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
	local cmd_parts = { "jj", "abandon" }
	if ignore_immut then
		table.insert(cmd_parts, "--ignore-immutable")
	end

	table.insert(cmd_parts, revsets)

	-- Build cmd string
	local cmd = table.concat(cmd_parts, " ")

	-- Try to execute cmd
	runner.execute_command_async(cmd, function()
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
				local cmd = string.format("jj git fetch --remote %s", choice.name)
				runner.execute_command_async(cmd, function()
					utils.notify(string.format("Fetching from %s...", choice), vim.log.levels.INFO)
					M.log({})
				end, "Error fetching from remote")
			end
		end)
	else
		-- Only one remote, fetch from it directly
		local cmd = "jj git fetch"
		utils.notify("Fetching from remote...", vim.log.levels.INFO)
		runner.execute_command_async(cmd, function()
			utils.notify("Successfully fetched from remote", vim.log.levels.INFO)
			M.log({})
		end, "Error fetching from remote")
	end
end

--- Handle pushing from `jj log` buffer.
function M.handle_log_push_all()
	local cmd = "jj git push"
	utils.notify("Pushing `ALL` bookmarks", vim.log.levels.INFO)
	runner.execute_command_async(cmd, function(output)
		if output and string.find(output, "Nothing changed%.") then
			utils.notify("Nothing changed.", vim.log.levels.INFO)
		else
			utils.notify("Successfully pushed all to remote", vim.log.levels.INFO)
			M.log({})
		end
	end, "Error pushing to remote")
end

--- Handle log pushing bookmark from current line in `jj log` buffer.
function M.handle_log_push_bookmark()
	local revset = get_revset()
	if not revset or revset == "" then
		return
	end
	-- If we found a revfision get it's bookmark and push it
	local bookmark, success = runner.execute_command(
		string.format("jj log -r %s -T 'bookmarks' --no-graph", revset),
		string.format("Error retrieving bookmark for `%s`", revset),
		nil,
		false
	)
	if not success or not bookmark then
		return
	end

	-- If there's a * trim it (bookmarks with modifications have *)
	bookmark = bookmark:gsub("%*", ""):gsub("^%s+", ""):gsub("%s+$", "")

	if bookmark == "" then
		utils.notify("No bookmark found for revision", vim.log.levels.ERROR)
		return
	end

	-- Push the bookmark from the revset found
	local cmd = string.format("jj git push --bookmark %s -N", bookmark)
	utils.notify(string.format("Pushing bookmark `%s`...", bookmark), vim.log.levels.INFO)
	runner.execute_command_async(cmd, function(output)
		if output and string.find(output, "Nothing changed%.") then
			utils.notify("Nothing changed.", vim.log.levels.INFO)
		else
			utils.notify(string.format("Successfully pushed bookmark for `%s`", revset), vim.log.levels.INFO)
			M.log({})
		end
	end, string.format("Error pushing bookmark for `%s`", revset))
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
	local bookmark, success = runner.execute_command(
		string.format("jj log -r %s -T 'bookmarks' --no-graph", revset),
		string.format("Error retrieving bookmark for `%s`", revset),
		nil,
		false
	)

	if not success or not bookmark then
		return
	end

	-- Trim and clean the bookmark (remove asterisks and whitespace)
	bookmark = bookmark:match("^%*?(.-)%*?$"):gsub("%s+", "")

	if bookmark == "" then
		utils.notify("[OPEN PR] No bookmark found for revision", vim.log.levels.ERROR)
		return
	end

	-- Open the PR using the utility function
	utils.open_pr_for_bookmark(bookmark)
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
						local cmd = string.format("jj bookmark create %s -r %s", input, revset)
						runner.execute_command_async(cmd, function()
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
				local cmd = string.format("jj bookmark move %s --to %s", choice, revset)
				runner.execute_command_async(cmd, function()
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

--- Quick squash the bookmark under the cursor into it's parent
function M.handle_log_quick_squash()
	local revset = get_revset()
	if not revset or revset == "" then
		return
	end

	local cmd = string.format("jj squash -r %s -u --ignore-immutable", revset)
	utils.notify(string.format("Squashing `%s` into it's parent...", revset), vim.log.levels.INFO)
	runner.execute_command_async(cmd, function()
		utils.notify(string.format("Successfully squashed `%s` into it's parent", revset), vim.log.levels.INFO)
		M.log({})
	end, string.format("Error squashing `%s` into it's parent", revset))
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
			modes = { "n" },
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
			desc = "Push all to remote",
			handler = M.handle_log_push_all,
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
		quick_squash = {
			desc = "Squash the bookmark under the cursor into it's parent (-r) keeping parent's message (-u), alwas ignores immutability",
			handler = M.handle_log_quick_squash,
			modes = { "n" },
		},
	}

	return cmd.merge_keymaps(cmd.resolve_keymaps_from_specs(keymaps, specs), cmd.terminal_keymaps())
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
			modes = { "n" },
		},
	}

	return cmd.resolve_keymaps_from_specs(keymaps, spec)
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
			modes = { "n" },
		},
	}

	return cmd.resolve_keymaps_from_specs(keymaps, spec)
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
	end
	return {}
end

--- Transition between buffer modes by swapping keymaps
--- @param target_mode "normal"|"rebase"|"squash" Target mode name (e.g., "normal", "rebase")
function M.transition_mode(target_mode)
	-- Get the mode keymaps
	if target_mode == vim.b.jj_mode then
		return
	end

	-- Get new keymaps for target mode
	local new_keymaps = M.get_keymaps_for_mode(target_mode)
	terminal.replace_terminal_keymaps(new_keymaps)

	-- Set up or tear down rebase mode autocmd
	if target_mode ~= "normal" then
		rebase_mode_autocmd_id = vim.api.nvim_create_autocmd("CursorMoved", {
			buffer = terminal.state.buf,
			callback = update_special_mode_target_highlight,
		})
		-- Highlight initial position
		update_special_mode_target_highlight()
	elseif rebase_mode_autocmd_id then
		vim.api.nvim_del_autocmd(rebase_mode_autocmd_id)
		rebase_mode_autocmd_id = nil
		-- Clear target highlight
		local buf = terminal.state.buf or 0
		vim.api.nvim_buf_clear_namespace(buf, log_special_mode_target_ns_id, 0, -1)
		last_rebase_target_line = nil
	end

	-- Update buffer mode state
	vim.b.jj_mode = target_mode
end

--- Handle special mode exit
function M.handle_special_mode_exit()
	-- Clear stored revsets
	vim.b.jj_rebase_revsets = nil

	M.transition_mode("normal")
	-- Clear highlights
	local buf = terminal.state.buf or 0
	vim.api.nvim_buf_clear_namespace(buf, log_selected_ns_id, 0, -1)
	vim.api.nvim_buf_clear_namespace(buf, log_special_mode_target_ns_id, 0, -1)

	utils.notify("Rebase `canceled`", vim.log.levels.INFO, 500)
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
	local cmd = string.format("jj rebase -r '%s' %s %s", revsets, mode_flat, destination_revset)

	-- If ignore_immut is true, add the flag
	-- This is not currently exposed in keymaps but could be in the future
	if ignore_immut then
		cmd = cmd .. " --ignore-immutable"
	end

	runner.execute_command_async(cmd, function()
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
	end, "Error during rebase onto")
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
	local cmd = string.format("jj squash -f '%s' -u", revsets)

	if mode == "into" then
		cmd = cmd .. string.format(" -t %s", destination_revset)
	end

	-- If ignore_immut is true, add the flag
	-- This is not currently exposed in keymaps but could be in the future
	if ignore_immut then
		cmd = cmd .. " --ignore-immutable"
	end

	runner.execute_command_async(cmd, function()
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
	end, "Error during squash into")
end

return M
