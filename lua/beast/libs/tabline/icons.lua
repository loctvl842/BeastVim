local M = {}

---@type table<string, string>
local cache = {}

---@type table?  Per-state resolved styles injected by highlights.lua
local state_styles = nil

--- Monotonic counter bumped on every clear_cache(). Checked by render() to
--- detect a palette change that requires a full tabline rebuild.
M._generation = 0

--- Receive resolved per-state styles from highlights.lua so icon highlights
--- mirror the cell's underline + sp without duplicating defaults.
---@param styles table { selected = {...}, visible = {...}, normal = {...} }
function M.set_state_styles(styles)
	state_styles = styles
end

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

	local style
	if state_styles then
		style = is_selected and state_styles.selected
			or (is_visible and state_styles.visible or state_styles.normal)
	else
		-- Fallback (should not happen in practice — highlights.lua runs at setup)
		local p = Palette.get()
		local active_bg = p.background
		local inactive_bg = Util.colors.lighten(p.background, 15)
		style = is_selected and { bg = active_bg, sp = p.accent3, underline = true }
			or (is_visible and { bg = active_bg, sp = p.dimmed4, underline = true } or { bg = inactive_bg, sp = p.dimmed4, underline = true })
	end

	local name = "BeastTlIcon_" .. key:gsub("[^%w_]", "_")
	vim.api.nvim_set_hl(0, name, {
		fg = icon_color,
		bg = style.bg,
		sp = style.sp,
		underline = style.underline,
	})
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
