local M = {}
local cmd = require("jj.cmd")
local picker = require("jj.picker")
local editor = require("jj.ui.editor")
local terminal = require("jj.ui.terminal")
local diff = require("jj.diff")
local browse = require("jj.browse")
local file = require("jj.file")

--- Jujutsu plugin configuration
--- @class jj.Config
--- @field cmd? jj.cmd.opts Options for command module
--- @field picker? jj.picker.config Options for picker module
--- @field terminal? jj.ui.terminal.opts Options for the terminal
--- @field editor? jj.ui.editor.opts Options for the editor module
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
	editor = {
		auto_insert = false,
		window = {
			type = "hsplit",
			split_size = 0.5,
			floating_width = 0.99,
			floating_height = 0.95,
		},
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
	terminal = {
		cursor_render_delay = 10,
		window = {
			type = "hsplit",
			split_size = 0.5,
			floating_width = 0.99,
			floating_height = 0.95,
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
	picker.setup(M.config.picker)
	editor.setup(M.config.editor)
	cmd.setup(M.config.cmd)
	terminal.setup(M.config.terminal)
	diff.setup(M.config.diff)

	-- Register the commands form the different modules
	cmd.register_command()
	browse.register_command()
	diff.register_command()
	file.register_command()
end

return M
