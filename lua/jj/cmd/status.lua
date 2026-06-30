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
	local file_info = parser.parse_file_info_from_status_line(vim.api.nvim_get_current_line())
	if not file_info then
		return
	end

	if file_info.is_rename then
		local restore_cmd = {
			"jj",
			"restore",
			"--from",
			"@-",
			jj_args.fileset(file_info.old_path),
			jj_args.fileset(file_info.new_path),
		}

		local _, restore_success = runner.execute_argv(restore_cmd, "Failed to restore original file")
		if restore_success then
			utils.notify("Reverted rename: " .. file_info.new_path .. " -> " .. file_info.old_path, vim.log.levels.INFO)
			require("jj.cmd").status()
		end
	else
		-- For non-renamed files, use regular restore
		local restore_cmd = { "jj", "restore", jj_args.fileset(file_info.old_path) }

		local _, success = runner.execute_argv(restore_cmd, "Failed to restore")
		if success then
			utils.notify("Restored: " .. file_info.old_path, vim.log.levels.INFO)
			require("jj.cmd").status()
		end
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
	local specs = {
		open_file = {
			desc = "Open file under cursor",
			handler = M.handle_status_enter,
		},
		restore_file = {
			desc = "Restore file under cursor",
			handler = M.handle_status_restore,
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
		local output, success = runner.execute_argv(cmd, "Failed to get status")
		if success then
			utils.notify(output and output or "", vim.log.levels.INFO)
		end
	else
		-- Default behavior: show in buffer
		terminal.run(cmd, M.status_keymaps())
	end
end

return M
