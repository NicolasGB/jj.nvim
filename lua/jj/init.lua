local M = {}
local cmd = require("jj.cmd")
local picker = require("jj.picker")
local utils = require("jj.utils")

--- Jujutsu plugin configuration
--- @class jj.Config
M.config = {
	-- Default configuration
	--- @type jj.picker.config
	picker = {
		snacks = {},
	},
	--- @type jj.utils.highlights Highlight configuration for describe buffer
	highlights = {
		added = { fg = "#3fb950", ctermfg = "Green" },
		modified = { fg = "#56d4dd", ctermfg = "Cyan" },
		deleted = { fg = "#f85149", ctermfg = "Red" },
		renamed = { fg = "#d29922", ctermfg = "Yellow" },
	},
	--- @type string Editor mode for describe command: "buffer" (Git-style editor) or "input" (simple input prompt)
	describe_editor = "buffer",
}

--- Setup the plugin
--- @param opts jj.Config: Options to configure the plugin
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	picker.setup(opts and opts.picker or {})
	utils.setup({ highlights = M.config.highlights })

	-- Pass describe_editor config to cmd module
	if opts and opts.describe_editor then
		cmd.config.describe_editor = opts.describe_editor
	end

	cmd.register_command()
end

return M
