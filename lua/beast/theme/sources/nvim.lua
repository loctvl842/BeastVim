--- Neovim's own colorschemes (`$VIMRUNTIME/colors`).
--- Derive the palette from Neovim's named colors (NvimLight*/NvimDark*), which
--- expose a stable, role-aware palette. Use them as the source of truth instead
--- of syntax groups (which may be unstyled, linked, or re-styled by our own
--- highlight modules, creating feedback loops on refresh).
local palette = require("beast.theme.palette")

---@type Beast.Theme.Source
local M = { name = "nvim" }

---@param name string
---@return boolean
function M.matches(name)
	return require("beast.theme.sources").colorscheme_exists(vim.env.VIMRUNTIME .. "/colors", name)
end

---@param name string
---@param fallback string
---@return string
local function named(name, fallback)
	local rgb = vim.api.nvim_get_color_by_name(name)
	if rgb < 0 then
		return fallback
	end
	return string.format("#%06x", rgb)
end

---@return Beast.Theme.Palette
function M.extract()
	local d = palette.defaults
	local background = palette.extract("Normal", "bg", d.background)
	local text = palette.extract("Normal", "fg", d.text)
	local blend = Util.colors.blend

	local light = vim.o.background == "dark" and "NvimLight" or "NvimDark"

	return {
		dark2 = blend(text, 0.15, background), -- #33353a
		dark1 = blend(text, 0.1, background), -- #282a30
		background = background,
		text = text,
		accent1 = named(light .. "Red", d.accent1), -- #ffc0b9
		accent2 = named(light .. "Yellow", d.accent2), -- #fce094
		accent3 = named(light .. "Green", d.accent3), -- #b3f6c0
		accent4 = named(light .. "Cyan", d.accent4), -- #8cf8f7
		accent5 = named(light .. "Blue", d.accent5), -- #a6dbff
		accent6 = named(light .. "Magenta", d.accent6), -- #ffcaff
		dimmed1 = blend(text, 0.75, background), -- #adafb6
		dimmed2 = blend(text, 0.55, background), -- #84868d
		dimmed3 = blend(text, 0.40, background), -- #66686e
		dimmed4 = blend(text, 0.25, background), -- #47494f
		dimmed5 = blend(text, 0.10, background), -- #282a30
	}
end

M.post_apply = palette.override_statusline

return M
