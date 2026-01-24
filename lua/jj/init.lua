local M = {}
local cmd = require("jj.cmd")
local picker = require("jj.picker")
local editor = require("jj.ui.editor")
local terminal = require("jj.ui.terminal")
local diff = require("jj.diff")

--- Jujutsu plugin configuration
--- @class jj.Config
--- @field cmd? jj.cmd.opts Options for command module
--- @field picker? jj.picker.config Options for picker module
--- @field terminal? jj.ui.terminal.opts Options for the terminal
--- @field highlights? jj.highlights Options for the highlights
--- @field diff? jj.diff.config Options for the diff module

--- @class jj.highlights
--- @field editor? jj.ui.editor.highlights Highlight configuration for describe buffer
--- @field log? jj.cmd.log.highlights Highlight configuration for the log buffer

---@type jj.Config
M.config = {
	picker = {
		snacks = {},
	},
	highlights = {
		editor = {
			renamed = { fg = "#d29922", ctermfg = "Yellow" },
		},
		log = {
			selected = { bg = "#3d2c52", ctermbg = "DarkMagenta" },
			targeted = { fg = "#5a9e6f", ctermfg = "Green" },
		},
	},
	diff = {
		backend = "native",
		backends = {},
	},
}

--- Setup the plugin
--- @param opts jj.Config: Options to configure the plugin
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	-- Setup for sub-modules
	picker.setup(opts and opts.picker or {})
	editor.setup({ highlights = M.config.highlights.editor })
	cmd.setup(opts and opts.cmd or {})
	terminal.setup(opts and opts.terminal or {})
	diff.setup(M.config.diff)

	cmd.register_command()
end

return M
