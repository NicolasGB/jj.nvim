--- @class jj.cmd.log
local M = {}

local utils = require("jj.utils")
local runner = require("jj.core.runner")
local parser = require("jj.core.parser")
local terminal = require("jj.ui.terminal")

local log_selected_hl_group = "JJLogSelectedHlGroup"
local log_selected_ns_id = vim.api.nvim_create_namespace(log_selected_hl_group)

--- @class jj.cmd.log_opts
--- @field summary? boolean
--- @field reversed? boolean
--- @field no_graph? boolean
--- @field limit? uinteger
--- @field revisions? string
--- @field raw_flags? string

---@type jj.cmd.log_opts
local default_log_opts = { summary = false, reversed = false, no_graph = false, limit = 20, raw_flags = nil }

--- Gets revset from current line or parent in case we're on a description node (QOL improvement).
--- Attempts to parse the revision from the current line. If not found and we're not on
--- the first line, falls back to parsing the previous line.
--- @return string|nil The revset if found in either current line or previous line, nil otherwise
local function get_revset()
	-- Try to extract revset from current line
	local line = vim.api.nvim_get_current_line()
	local revset = parser.get_revset(line)

	-- Fallback: check previous line if current line didn't yield a revset
	-- This handles cases where cursor is on a wrapped/description line
	if not revset then
		local current_line_num = vim.api.nvim_win_get_cursor(0)[1]
		if current_line_num > 1 then
			-- Get the previous line (buf_get_lines is 0-indexed, so we subtract 2)
			local prev_line = vim.api.nvim_buf_get_lines(0, current_line_num - 2, current_line_num - 1, false)[1]
			revset = parser.get_revset(prev_line)
		end
	end

	return revset
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
		-- Normal mode: current or previous line
		local current_line_num = vim.api.nvim_win_get_cursor(0)[1]
		local line = vim.api.nvim_get_current_line()
		local line_num = current_line_num

		-- Se if cursor is already on a revset line otherwise fetch it's n-1
		if not parser.get_revset(line) and current_line_num > 1 then
			line_num = current_line_num - 1
			line = vim.api.nvim_buf_get_lines(buf, line_num - 1, line_num, false)[1]
		end

		-- Now try and find the revset for highlighting
		if parser.get_revset(line) then
			-- Get the next line (description)
			local next_line = vim.api.nvim_buf_get_lines(buf, line_num, line_num + 1, false)[1] or ""
			table.insert(marks, {
				line = line_num - 1,
				col = 0,
				end_line = line_num,
				end_col = #next_line,
			})
		end
	end

	return marks
end

--- Init log highlight groups
function M.init_log_highlights()
	local cfg = require("jj.cmd").config.log
	if not cfg then
		return
	end

	vim.api.nvim_set_hl(0, log_selected_hl_group, cfg.selected_hl)
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
	local revset = get_revset()
	if not revset or revset == "" then
		return
	end

	-- Mapping for flag-specific options and messages.
	local flag_map = {
		after = {
			opt = "-A",
			err = "Error creating new change after: `%s`",
			ok = "Successfully created change after: `%s`",
		},
		default = {
			opt = "",
			err = "Error creating new change branching off `%s`",
			ok = "Successfully created change branching off `%s`",
		},
	}

	local cfg = flag_map[flag] or flag_map.default

	-- Build command parts
	local cmd_parts = { "jj", "new" }
	if cfg.opt ~= "" then
		table.insert(cmd_parts, cfg.opt)
	end
	table.insert(cmd_parts, revset)
	if ignore_immut then
		table.insert(cmd_parts, "--ignore-immutable")
	end

	local cmd = table.concat(cmd_parts, " ")
	runner.execute_command_async(cmd, function()
		utils.notify(string.format(cfg.ok, revset), vim.log.levels.INFO)
		-- Refresh the log buffer after creating the change.
		require("jj.cmd").log()
	end, string.format(cfg.err, revset))
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
	local revset = get_revset()
	if not revset or revset == "" then
		return
	end

	-- If we found a revision, abandon it.

	-- Build command parts.
	local cmd_parts = { "jj", "abandon" }
	if ignore_immut then
		table.insert(cmd_parts, "--ignore-immutable")
	end

	table.insert(cmd_parts, revset)

	-- Build cmd string
	local cmd = table.concat(cmd_parts, " ")

	-- Try to execute cmd
	runner.execute_command_async(cmd, function()
		utils.notify(string.format("Abandoned change: `%s`", revset), vim.log.levels.INFO)
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
	local buf = terminal.state.buf
	if not buf then
		utils.notify("No open log buffer", vim.log.levels.ERROR)
		return
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
			return
		end

		revsets_str = table.concat(revsets, " | ")
		-- Exit visual mode before transition
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
	else
		return
	end

	-- Validate revsets
	if not revsets_str or revsets_str == "" then
		return
	end

	vim.b.jj_rebase_revsets = revsets_str

	-- Set highlights
	local marks = get_highlight_marks()
	if not marks or #marks == 0 then
		utils.notify("No valid revisions found to highlight during rebase", vim.log.levels.ERROR)
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

	M.transition_mode("rebase")
	utils.notify("Rebase `started`.", vim.log.levels.INFO, 500)
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
			modes = { "n" },
		},
		new_after = {
			desc = "Create new change after revision under cursor",
			handler = M.handle_log_new,
			args = { "after", false },
			modes = { "n" },
		},
		new_after_immutable = {
			desc = "Create new change after revision under cursor (ignore immutable)",
			handler = M.handle_log_new,
			args = { "after", true },
			modes = { "n" },
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
			modes = { "n" },
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
		exit_mode = {
			desc = "Exit rebase to normal mode",
			handler = M.handle_rebase_mode_exit,
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
	end
	return {}
end

--- Transition between buffer modes by swapping keymaps
--- @param target_mode string Target mode name (e.g., "normal", "rebase")
function M.transition_mode(target_mode)
	-- Get the mode keymaps
	if target_mode == vim.b.jj_mode then
		return
	end

	-- Get new keymaps for target mode
	local new_keymaps = M.get_keymaps_for_mode(target_mode)
	terminal.replace_terminal_keymaps(new_keymaps)

	-- Update buffer mode state
	vim.b.jj_mode = target_mode
end

--- Handle rebase mode exit
function M.handle_rebase_mode_exit()
	-- Clear stored revsets
	vim.b.jj_rebase_revsets = nil

	M.transition_mode("normal")
	-- Clear highlights
	local buf = terminal.state.buf or 0
	vim.api.nvim_buf_clear_namespace(buf, log_selected_ns_id, 0, -1)

	utils.notify("Rebase operation `canceled`", vim.log.levels.INFO, 500)
end

--- Handle rebase execution with mode
--- @param mode "onto" | "after" | "before" Rebase mode
function M.handle_rebase_execute(mode)
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

	local cmd = string.format("jj rebase -r '%s' %s %s", revsets, mode_flat, destination_revset)
	runner.execute_command_async(cmd, function()
		utils.notify(
			string.format("Rebased `%s` %s `%s` successfully", revsets, mode, destination_revset),
			vim.log.levels.INFO
		)
		vim.b.jj_rebase_revsets = nil

		M.transition_mode("normal")
		-- Refresh log
		M.log({})
	end, "Error during rebase onto")
end

return M
