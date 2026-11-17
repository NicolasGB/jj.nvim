--- Explicit operation context. Capture once, then keep it in callback closures.
local M = {}

--- Resolve against the effective invoking window/tab directory, before routing UI.
function M.cwd(cwd)
	if cwd == nil then
		return vim.fn.getcwd()
	end
	if type(cwd) ~= "string" or cwd == "" then
		error("cwd must be a non-empty directory path")
	end
	if not require("jj.utils").is_absolute_path(cwd) then
		cwd = vim.fs.joinpath(vim.fn.getcwd(), cwd)
	end
	return vim.fs.normalize(cwd)
end

function M.capture(opts)
	return { cwd = M.cwd(opts and opts.cwd) }
end

--- Only UI actions inherit buffer context. Public log() always captures afresh.
function M.from_buffer(buf)
	local ctx = vim.b[buf or 0].jj_context
	if ctx then
		return ctx
	end
	-- A named revision can also be reopened after its buffer metadata is gone.
	local _, _, cwd = require("jj.utils").parse_jj_uri(vim.api.nvim_buf_get_name(buf or 0))
	return M.capture({ cwd = cwd })
end

function M.attach(buf, ctx)
	if buf and vim.api.nvim_buf_is_valid(buf) then
		vim.b[buf].jj_context = ctx
	end
end

function M.refresh(ctx, overrides)
	local opts = vim.tbl_extend("force", ctx.log_opts or {}, overrides or {}, { cwd = ctx.cwd })
	return require("jj.cmd.log").log(opts)
end

return M
