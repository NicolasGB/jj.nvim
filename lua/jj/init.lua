local M = {}
local cmd = require("jj.cmd")
local picker = require("jj.picker")
local editor = require("jj.ui.editor")
local diff = require("jj.diff")
local utils = require("jj.utils")

--- Jujutsu plugin configuration
--- @class jj.Config
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
	--- @type "buffer"|"input" Editor mode for describe command: "buffer" (Git-style editor) or "input" (simple input prompt)
	describe_editor = "buffer",
}

--- Setup the plugin
--- @param opts jj.Config: Options to configure the plugin
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	-- Setup for sub-modules
	picker.setup(opts and opts.picker or {})
	editor.setup({ highlights = M.config.highlights })
	utils.setup(opts) -- Keep for future-proofing, even if it's a no-op now

	-- Pass describe_editor config to cmd module
	if opts and opts.describe_editor then
		cmd.config.describe_editor = opts.describe_editor
	end

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
