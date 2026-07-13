--- @class jj.cmd.status
local M = {}

local utils = require("jj.utils")
local runner = require("jj.core.runner")
local parser = require("jj.core.parser")
local terminal = require("jj.ui.terminal")
local jj_args = require("jj.core.args")

--- Handle restoring a file from the jj status buffer
--- Supports both renamed and non-renamed files
function M.handle_status_restore()
	local lines = utils.get_visual_selection(terminal.state.buf)
	if not lines then
		lines = { vim.api.nvim_get_current_line() }
	end

	--- @type jj.core.parser.status_file[]
	local files = {}

	for _, line in ipairs(lines) do
		local file_info = parser.parse_file_info_from_status_line(line)
		if file_info then
			table.insert(files, file_info)
		end
	end

	-- Return early if no files were found in the selection
	if #files == 0 then
		utils.notify("No files selected to restore", vim.log.levels.WARN)
		return
	end

	-- For each file found restore it
	local cmd = { "jj", "restore" }
	for _, file in ipairs(files) do
		if file.is_rename then
			-- If it's a rename add both old and new paths to the restore command
			vim.list_extend(cmd, { jj_args.fileset(file.old_path), jj_args.fileset(file.new_path) })
		else
			table.insert(cmd, jj_args.fileset(file.old_path))
		end
	end

	local _, restore_success = runner.execute(cmd, "Failed to restore original file")
	if restore_success then
		local notif_msg = "Restored file:\n"
		if #files > 1 then
			notif_msg = "Restored files:\n"
		end

		for _, file in ipairs(files) do
			if file.is_rename then
				notif_msg = notif_msg .. "- `" .. file.old_path .. "` -> `" .. file.new_path .. "`\n"
			else
				notif_msg = notif_msg .. "- `" .. file.old_path .. "`\n"
			end
		end
		utils.notify(notif_msg, vim.log.levels.INFO)
		M.status() -- Refresh the status buffer after restoring files
	end
end

--- Handle opening a file from the jj status buffer
function M.handle_status_enter()
	local file_info = parser.parse_file_info_from_status_line(vim.api.nvim_get_current_line())

	if not file_info then
		return
	end

	if require("jj").config.terminal.window.type == "floating" then
		terminal.close_floating_buffer()
	end

	local filepath = file_info.new_path
	local stat = vim.uv.fs_stat(filepath)
	if not stat then
		utils.notify("File not found: " .. filepath, vim.log.levels.ERROR)
		return
	end

	-- Go to the previous window (split above)
	vim.cmd("wincmd p")

	-- Open the file in that window, replacing current buffer
	vim.cmd("edit " .. vim.fn.fnameescape(filepath))
end

--- Resolve status keymaps from config
--- @return jj.core.buffer.keymap[]
function M.status_keymaps()
	local cmd = require("jj.cmd")
	local cfg = cmd.config.keymaps.status or {}

	--- @type jj.cmd.keymap_specs
	local specs = {
		open_file = {
			desc = "Open file under cursor",
			handler = M.handle_status_enter,
			modes = { "n" },
		},
		restore_file = {
			desc = "Restore file under cursor",
			handler = M.handle_status_restore,
			modes = { "n", "v" },
		},
	}

	return cmd.resolve_keymaps_from_specs(cfg, specs)
end

--- Jujutsu status
--- @param opts? table Options for the status command
function M.status(opts)
	if not utils.ensure_jj() then
		return
	end

	local cmd = { "jj", "status", "--no-pager" }

	if opts and opts.notify then
		local output, success = runner.execute(cmd, "Failed to get status")
		if success then
			utils.notify(output and output or "", vim.log.levels.INFO)
		end
	else
		-- Default behavior: show in buffer
		terminal.run(cmd, M.status_keymaps())
	end
end

return M
