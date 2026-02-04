--- @class jj.cmd.describe
local M = {}

local utils = require("jj.utils")
local runner = require("jj.core.runner")
local terminal = require("jj.ui.terminal")
local editor = require("jj.ui.editor")

--- @class jj.cmd.describe_opts
--- @field with_status boolean: Whether or not `jj st` should be displayed in a buffer while describing the commit
--- @field type? "buffer"|"input" Editor mode for describe command: "buffer" (Git-style editor) or "input" (simple input prompt)
--- @type jj.cmd.describe_opts
local default_describe_opts = {
	with_status = true,
}

--- Execute jj describe command with the given description
--- @param description string The description text
--- @param revset? string The revision to describe
local function execute_describe(description, revset)
	if not description or description == "" then
		utils.notify("Description cannot be empty", vim.log.levels.ERROR)
		return
	end

	local cmd = "jj describe"
	if revset then
		cmd = cmd .. " -r " .. revset
	end
	cmd = cmd .. " --stdin"

	-- Use --stdin to properly handle multi-line and special characters
	runner.execute_command_async(cmd, function()
		utils.notify("Description set.", vim.log.levels.INFO)
	end, "Failed to describe", description)
end

--- Resolve describe editor keymaps from config
--- @return jj.core.buffer.keymap
local function describe_editor_keymaps()
	local cmd = require("jj.cmd")
	local cfg = cmd.config.describe.editor.keymaps or {}
	return cmd.resolve_keymaps_from_specs(cfg, {
		close = {
			desc = "Close describe editor without saving",
			handler = "<cmd>close!<CR>",
		},
	})
end

--- Jujutsu describe
--- @param description? string Optional description text
--- @param revset? string The revision to describe
--- @param opts? jj.cmd.describe_opts Optional command options
--- @param on_close function|nil Optional callback when editor is closed
function M.describe(description, revset, opts, on_close)
	if not utils.ensure_jj() then
		return
	end

	-- Check if a description was provided otherwise require for input
	if description then
		-- Description provided directly
		execute_describe(description, revset)
		return
	end

	if not revset then
		revset = "@"
	end

	local cmd = require("jj.cmd")
	local merged_opts = vim.tbl_deep_extend("force", default_describe_opts, opts or {})

	-- Use buffer editor mode (defaults to "buffer" if not configured)
	local editor_mode = merged_opts.type or cmd.config.describe.editor.type or "buffer"
	if editor_mode == "buffer" then
		local text = utils.get_describe_text(revset)
		if not text then
			return
		end

		-- Close the terminal buffer before opening editor
		terminal.close_terminal_buffer()

		editor.open_editor(text, function(buf_lines)
			local trimmed_description = utils.extract_description_from_describe(buf_lines)
			if not trimmed_description then
				-- If nothing is provide simply exit
				return
			end
			execute_describe(trimmed_description, revset)
			-- Once editing is done, reopen the log if we came from there
		end, function()
			-- If an on close callback is provided, call it
			if on_close then
				vim.schedule(function()
					on_close()
				end)
			end
		end, describe_editor_keymaps())
	else
		-- Use input mode
		if merged_opts.with_status then
			-- Show the status in a terminal buffer
			cmd.status()
		end

		vim.ui.input({
			prompt = "Description: ",
			default = "",
		}, function(input)
			-- If the user inputed something, execute the describe command
			if input then
				execute_describe(input, revset)
			end
			-- Close the current terminal when finished
			terminal.close_terminal_buffer()
			if on_close then
				vim.schedule(function()
					on_close()
				end)
			end
		end)
	end
end

return M
