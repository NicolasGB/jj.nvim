--- Window routing for actions launched from jj views.
local M = {}

--- Whether a window can be used without replacing a special-purpose view.
--- @param win integer|nil
--- @return boolean
function M.is_editor(win)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return false
	end
	local buf = vim.api.nvim_win_get_buf(win)
	return vim.api.nvim_win_get_config(win).relative == ""
		and not vim.wo[win].winfixbuf
		and not vim.wo[win].diff
		and vim.bo[buf].buftype == ""
end

--- Read an origin candidate from the current window without changing focus or state.
--- Returns the current window if `is_editor()` accepts it; otherwise reads its
--- window-local `jj_origin_win`, which jj view constructors copy from their caller.
--- This does not set that variable, walk a chain of windows, or validate the stored
--- ID: it may be nil or refer to a closed/non-editor window. `enter()` checks whether
--- the candidate is usable and falls back to another editor or a new split.
--- @return integer|nil origin Current editor ID, or the view's stored origin candidate.
function M.get_origin()
	local win = vim.api.nvim_get_current_win()
	if M.is_editor(win) then
		return win
	end
	return vim.w[win].jj_origin_win
end

--- Store a previously captured origin candidate on a jj view window.
--- Capture it with `get_origin()` before creating or closing views. This only
--- writes window-local metadata: it does not change focus, recapture the origin,
--- or validate the candidate. Pass nil to clear it; `enter()` validates on use.
--- @param win integer Window receiving the origin metadata.
--- @param origin integer|nil Origin candidate to store, or nil to clear.
function M.set_origin(win, origin)
	vim.w[win].jj_origin_win = origin
end

--- Whether replacing a window's buffer preserves any unsaved changes.
--- @param win integer|nil
--- @return boolean
local function can_replace(win)
	if not win or not M.is_editor(win) then
		return false
	end
	local buf = vim.api.nvim_win_get_buf(win)
	if not vim.bo[buf].modified then
		return true
	end
	return vim.bo[buf].bufhidden == "hide"
		or (vim.o.hidden and vim.bo[buf].bufhidden == "")
		or #vim.fn.win_findbuf(buf) > 1
end

--- Select an editor window, make it current, and return its window ID.
--- Selection order:
--- 1. A usable editor in the current tab already displaying `path`.
--- 2. The usable originating editor, even if it is in another tab.
--- 3. Any other usable editor in the current tab.
--- 4. A new empty split in the current tab when no existing editor is usable.
--- Existing buffers are preserved: `path` only selects a destination; it is not opened.
--- Editors whose modified buffer cannot safely be hidden are skipped unless they
--- already display `path`; if no safe destination remains, a new split is created.
--- Usable editors exclude floats, pinned windows, diff windows, and special buffer types
--- (see `is_editor`). Selecting the origin may switch tabs; other searches stay in the current tab.
--- @param path? string File path used to prefer an existing editor; relative paths resolve against the current working directory.
--- @param origin? integer Originating editor window ID, usually captured before dismissing a view. Defaults to `M.get_origin()`; unusable origins are skipped.
--- @return integer win Selected window ID (also the current window); a new split is empty and has diff mode disabled.
function M.enter(path, origin)
	origin = origin or M.get_origin()
	local wins = vim.api.nvim_tabpage_list_wins(0)
	local full_path = path and vim.fn.fnamemodify(path, ":p")
	if full_path then
		for _, win in ipairs(wins) do
			if M.is_editor(win) and vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)) == full_path then
				vim.api.nvim_set_current_win(win)
				return win
			end
		end
	end
	if origin and can_replace(origin) then
		vim.api.nvim_set_current_win(origin)
		return origin
	end
	for _, win in ipairs(wins) do
		if can_replace(win) then
			vim.api.nvim_set_current_win(win)
			return win
		end
	end
	-- Splitting a floating window is not supported; use a tiled window first.
	for _, win in ipairs(wins) do
		if vim.api.nvim_win_get_config(win).relative == "" then
			vim.api.nvim_set_current_win(win)
			break
		end
	end
	-- A bare split copies the source buffer (often the status terminal). Start
	-- with an empty editor instead, so a subsequent routing pass can reuse it.
	vim.cmd("new")
	vim.cmd("diffoff")
	return vim.api.nvim_get_current_win()
end

return M
