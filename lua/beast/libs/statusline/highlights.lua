-- Beast.Statusline highlight refresh hook.
-- M.get() returns an empty table — the statusline doesn't emit any standalone
-- highlight groups itself; its highlights are JIT-built per component via
-- `hlgroup.lua`. The dispatcher only needs us to clear that JIT cache + force
-- a redraw, which lives in M.post_apply().

local M = {}

function M.get()
	return {}
end

function M.post_apply()
	require("beast.libs.statusline.hlgroup").clear_all()
	vim.cmd("redrawstatus")
end

return M
