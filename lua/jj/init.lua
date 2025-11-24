local M = {}
local cmd = require("jj.cmd")
local picker = require("jj.picker")
local editor = require("jj.ui.editor")
local terminal = require("jj.ui.terminal")

--- Jujutsu plugin configuration
--- @class jj.Config
--- @field cmd? jj.cmd.opts Options for command module
--- @field picker? jj.picker.config Options for picker module
--- @field terminal? jj.ui.terminal.opts Options for the terminal
--- @field highlights? jj.ui.editor.highlights Highlight configuration for describe buffer

M.config = {
	-- Default configuration
	--- @type jj.picker.config
	picker = {
		snacks = {},
	},
	--- @type jj.ui.editor.highlights Highlight configuration for describe buffer
	highlights = {},
}

--- Setup the plugin
--- @param opts jj.Config: Options to configure the plugin
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	-- Setup for sub-modules
	picker.setup(opts and opts.picker or {})
	editor.setup({ highlights = M.config.highlights })
	cmd.setup(opts and opts.cmd or {})
	terminal.setup(opts and opts.terminal or {})

	cmd.register_command()
end

return M
