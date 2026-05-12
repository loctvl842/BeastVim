local M = {}

---@type table<string, string>
local cache = {}

--- Ensure a highlight group exists for the given icon color and active state.
--- Creates the group lazily on first use and caches the name.
---@param icon_color string Hex color from devicons
---@param is_active boolean Whether the buffer cell is the active buffer
---@return string group_name The highlight group name to use in the format string
function M.ensure(icon_color, is_active)
	local key = icon_color .. (is_active and "_S" or "_V")
	if cache[key] then
		return cache[key]
	end

	local p = Palette.get()
	local active_bg = p.background
	local inactive_bg = Util.colors.lighten(p.background, 15)

	local name = "BeastTlIcon_" .. key:gsub("[^%w_]", "_")
	local hl = {
		fg = icon_color,
		bg = is_active and active_bg or inactive_bg,
	}
	if is_active then
		hl.underline = true
		hl.sp = p.accent3
	end
	vim.api.nvim_set_hl(0, name, hl)
	cache[key] = name
	return name
end

--- Clear all cached icon highlight groups.
--- Called by highlights.lua before re-creating static groups on ColorScheme change.
function M.clear_cache()
	for _, name in pairs(cache) do
		pcall(vim.api.nvim_set_hl, 0, name, {})
	end
	cache = {}
end

return M
