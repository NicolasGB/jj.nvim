--- @class jj.cmd.describe
local M = {}

local utils = require("jj.utils")
local runner = require("jj.core.runner")
local parser = require("jj.core.parser")
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
function M.describe(description, revset, opts)
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
		local jj_cmd = "jj log -r " .. revset .. " --no-graph -T 'coalesce(description, \"\n\")'"
		local old_description_raw, success = runner.execute_command(jj_cmd, "Failed to get old description")
		if not old_description_raw or not success then
			return
		end

		local log_cmd = "jj log -r " .. revset .. " --no-graph -T 'self.diff().summary()'"
		local status_result, success2 = runner.execute_command(log_cmd, "Error getting status")
		if not success2 then
			return
		end

		local status_files = parser.get_status_files(status_result)
		local old_description = vim.trim(old_description_raw)

		-- Split description into lines to preserve multiline descriptions
		local description_lines = vim.split(old_description, "\n")
		local text = {}
		for _, line in ipairs(description_lines) do
			table.insert(text, line)
		end
		table.insert(text, "") -- Empty line to separate from user input
		table.insert(text, "JJ: Change ID: " .. revset)
		table.insert(text, "JJ: This commit contains the following changes:")
		for _, item in ipairs(status_files) do
			table.insert(text, string.format("JJ:     %s %s", item.status, item.file))
		end
		table.insert(text, "JJ:") -- blank line
		table.insert(text, 'JJ: Lines starting with "JJ:" (like this one) will be removed')

		-- Check if we're coming from the log view so we can reopen it after editing
		local open_log_on_close = terminal.state.buf_cmd == "log"

		-- Close the terminal buffer before opening editor
		terminal.close_terminal_buffer()

		editor.open_editor(text, function(buf_lines)
			local user_lines = {}
			for _, line in ipairs(buf_lines) do
				if not line:match("^JJ:") then
					table.insert(user_lines, line)
				end
			end
			-- Join lines and trim leading/trailing whitespace
			local trimmed_description = table.concat(user_lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
			execute_describe(trimmed_description, revset)
			-- Once editing is done, reopen the log if we came from there
		end, function()
			if open_log_on_close then
				vim.schedule(function()
					cmd.log({})
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
		end)
	end
end

return M

