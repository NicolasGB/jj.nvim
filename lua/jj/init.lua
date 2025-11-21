local M = {}
local cmd = require("jj.cmd")
local picker = require("jj.picker")
local editor = require("jj.ui.editor")
local diff = require("jj.diff")
local utils = require("jj.utils")

--- Jujutsu plugin configuration
--- @class jj.Config
--- @field cmd? jj.cmd.opts Options for command module
--- @field picker? jj.picker.config Options for picker module
M.config = {
	-- Default configuration
	--- @type jj.picker.config
	picker = {
		snacks = {},
	},
	--- @type jj.ui.editor.highlights Highlight configuration for describe buffer
	highlights = {
		added = { fg = "#3fb950", ctermfg = "Green" },
		modified = { fg = "#56d4dd", ctermfg = "Cyan" },
		deleted = { fg = "#f85149", ctermfg = "Red" },
		renamed = { fg = "#d29922", ctermfg = "Yellow" },
	},
}

--- Setup the plugin
--- @param opts jj.Config: Options to configure the plugin
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	-- Setup for sub-modules
	picker.setup(opts and opts.picker or {})
	editor.setup({ highlights = M.config.highlights })
	cmd.setup(opts.cmd)
	utils.setup(opts) -- Keep for future-proofing, even if it's a no-op now

	cmd.register_command()

	-- Expose public API functions on the top-level module
	M.status = cmd.status
	M.describe = cmd.describe
	M.log = cmd.log
	M.new = cmd.new
	M.edit = cmd.edit
	M.squash = cmd.squash
	M.rebase = cmd.rebase
	M.undo = cmd.undo
	M.redo = cmd.redo
	M.bookmark_create = cmd.bookmark_create
	M.bookmark_delete = cmd.bookmark_delete
	M.j = cmd.j

	M.picker = {
		status = picker.status,
		file_history = picker.file_history,
	}

	M.diff = {
		vsplit = diff.open_vdiff,
		hsplit = diff.open_hdiff,
	}
end

return M
