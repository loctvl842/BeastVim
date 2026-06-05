---Per-tab mutable state for the window lib. Owned by init.lua; this module
---just provides accessor + cleanup helpers.
local api = vim.api

local M = {}

---@class Beast.Window.MaxSnapshot
---@field width? Beast.Window.WinResizeData[]
---@field height? Beast.Window.WinResizeData[]

---@type table<integer, Beast.Window.MaxSnapshot>
local maximized = {}

---@type table<integer, integer>
M.cursor_virtcol = {}

---augroup id for the autowidth-driven autocmds (owned by autocmds.lua).
---@type integer|nil
M.augroup_autowidth = nil

---augroup id for the maximize-guard autocmd (created lazily by init.lua).
---@type integer|nil
M.augroup_maximize = nil

---Single-flight flag for autowidth — flipped by autocmds while a resize is queued.
M.resizing_request = false

---Currently-running animation handle (nil when idle). Single-flight enforcement.
---@type Beast.Window.AnimationHandle|nil
M.animation = nil

---@param tab? integer Defaults to current tab.
---@return Beast.Window.MaxSnapshot|nil
function M.get_maximized(tab)
	tab = tab or api.nvim_get_current_tabpage()
	return maximized[tab]
end

---@param snapshot Beast.Window.MaxSnapshot|nil
---@param tab? integer
function M.set_maximized(snapshot, tab)
	tab = tab or api.nvim_get_current_tabpage()
	maximized[tab] = snapshot
end

---@param tab? integer
function M.clear_maximized(tab)
	tab = tab or api.nvim_get_current_tabpage()
	maximized[tab] = nil
end

---Drop state for tabs that no longer exist (called from TabClosed).
function M.gc_tabs()
	local alive = {}
	for _, t in ipairs(api.nvim_list_tabpages()) do
		alive[t] = true
	end
	for t in pairs(maximized) do
		if not alive[t] then
			maximized[t] = nil
		end
	end
end

return M
