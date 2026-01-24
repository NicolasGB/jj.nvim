---@class jj.diff
local M = {}

local utils = require("jj.utils")

---@alias jj.diff.backend "native"|"diffview"|"codediff"|string

---@class jj.diff.current_opts
---@field rev? string          -- revision to diff against (default: "@-")
---@field path? string         -- path to diff (default: current buffer path)
---@field backend? jj.diff.backend
---@field layout? "vertical"|"horizontal" -- only used by native backend

---@class jj.diff.revision_opts
---@field rev string           -- revision to show
---@field path? string         -- optional single-file filter
---@field backend? jj.diff.backend
---@field display? "floating"|"tab"|"split" -- hint to backend

---@class jj.diff.revisions_opts
---@field left string          -- left/base revision
---@field right string         -- right/target revision
---@field path? string         -- optional single-file filter
---@field backend? jj.diff.backend
---@field display? "floating"|"tab"|"split"

---@class jj.diff.BackendImpl
---@field diff_current? fun(opts: jj.diff.current_opts)
---@field show_revision? fun(opts: jj.diff.revision_opts)
---@field diff_revisions? fun(opts: jj.diff.revisions_opts)

---@class jj.diff.config
---@field backend? jj.diff.backend
---@field backends? table<string, table>

---@class jj.diff.diff_opts
---@field rev string the revision to diff against

---@type jj.diff.config
M.config = {
	backend = "native",
	backends = {},
}

---@type table<string, jj.diff.BackendImpl>
local backends = {}

-----------------------------------------------------------------------
-- Backend Registry
-----------------------------------------------------------------------

--- Register or override a backend implementation
---@param name string
---@param impl jj.diff.BackendImpl
function M.register_backend(name, impl)
	backends[name] = impl
end

--- Get the configured default backend name
---@return string
local function get_config_backend()
	local ok, cfg = pcall(function()
		return require("jj").config.diff
	end)
	if ok and cfg and cfg.backend then
		return cfg.backend
	end
	return M.config.backend or "native"
end

--- Get a backend implementation by name, falling back to native
---@param name? string
---@return jj.diff.BackendImpl
local function get_backend(name)
	name = name or get_config_backend()
	local impl = backends[name]
	if not impl then
		utils.notify(
			string.format("[Diff] backend '%s' not available, falling back to 'native'", name),
			vim.log.levels.WARN
		)
		impl = backends.native
	end
	return impl
end

--- Setup the diff module
---@param cfg? jj.diff.config
function M.setup(cfg)
	M.config = vim.tbl_deep_extend("force", M.config, cfg or {})
	-- Laod default backends
	pcall(require, "jj.diff.diffview")
	pcall(require, "jj.diff.codediff")
	pcall(require, "jj.diff.native")
end

-----------------------------------------------------------------------
-- Unified Public API
-----------------------------------------------------------------------

--- Single dispatcher (canonical entry point)
---@param kind "current"|"revision"|"revisions"
---@param opts table
function M.open(kind, opts)
	opts = opts or {}
	local backend = get_backend(opts.backend)

	if kind == "current" then
		if backend.diff_current then
			return backend.diff_current(opts)
		end
		return backends.native.diff_current(opts)
	elseif kind == "revision" then
		if backend.show_revision then
			return backend.show_revision(opts)
		end
		return backends.native.show_revision(opts)
	elseif kind == "revisions" then
		if backend.diff_revisions then
			return backend.diff_revisions(opts)
		end
		return backends.native.diff_revisions(opts)
	else
		utils.notify("[Diff] unknown diff kind: " .. tostring(kind), vim.log.levels.ERROR)
	end
end

--- Diff current buffer against a revision
---@param opts? jj.diff.current_opts
function M.diff_current(opts)
	return M.open("current", opts or {})
end

--- Show what changed in a single revision
---@param opts jj.diff.revision_opts
function M.show_revision(opts)
	return M.open("revision", opts)
end

--- Diff between two revisions
---@param opts jj.diff.revisions_opts
function M.diff_revisions(opts)
	return M.open("revisions", opts)
end

---
-----------------------------------------------------------------------
-- BACKWARDS COMPATIBLE API
-----------------------------------------------------------------------

-- Open a vertical diff split for a specific revision of the current file
--- @param opts? jj.diff.diff_opts Any passed arguments
function M.open_vdiff(opts)
	M.diff_current(vim.tbl_extend("force", { layout = "vertical" }, { rev = opts and opts.rev }))
end

-- Open a horizontal diff split for a specific revision of the current file
--- @param opts? jj.diff.diff_opts Any passed arguments
function M.open_hdiff(opts)
	M.diff_current(vim.tbl_extend("force", { layout = "horizontal" }, { rev = opts and opts.rev }))
end

return M
