local M = {}

---@type table<string, string>
local cache = {}

--- Monotonic counter bumped on every clear_cache(). Checked by render() to
--- detect a palette change that requires a full tabline rebuild.
M._generation = 0

--- Ensure a highlight group exists for the given icon color and buffer state.
--- Creates the group lazily on first use and caches the name.
---@param icon_color string Hex color from devicons
---@param is_selected boolean Whether the buffer cell is the selected buffer
---@param is_visible? boolean Whether the buffer is visible in a window (not selected)
---@return string group_name The highlight group name to use in the format string
function M.ensure(icon_color, is_selected, is_visible)
	local suffix = is_selected and "_S" or (is_visible and "_V" or "_N")
	local key = icon_color .. suffix
	if cache[key] then
		return cache[key]
	end

	local p = Palette.get()
	local active_bg = p.background
	local inactive_bg = Util.colors.lighten(p.background, 15)

	local name = "BeastTlIcon_" .. key:gsub("[^%w_]", "_")
	local hl = { fg = icon_color }
	if is_selected then
		hl.bg = active_bg
		hl.underline = true
		hl.sp = p.accent3
	elseif is_visible then
		hl.bg = active_bg
	else
		hl.bg = inactive_bg
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
	M._generation = M._generation + 1
end

return M
