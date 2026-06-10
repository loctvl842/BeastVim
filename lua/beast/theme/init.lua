---@class Beast.Palette
---@field dark2 string
---@field dark1 string
---@field background string
---@field text string
---@field accent1 string
---@field accent2 string
---@field accent3 string
---@field accent4 string
---@field accent5 string
---@field accent6 string
---@field dimmed1 string
---@field dimmed2 string
---@field dimmed3 string
---@field dimmed4 string
---@field dimmed5 string

---@class Beast.Theme
local M = {}

---@type Beast.Palette
local defaults = {
	dark2 = "#4f5258",
	dark1 = "#2c2e33",
	background = "#14161b",
	text = "#e0e2ea",
	accent1 = "#ffc0b9",
	accent2 = "#fce094",
	accent3 = "#b3f6c0",
	accent4 = "#8cf8f7",
	accent5 = "#a6dbff",
	accent6 = "#8cf8f7",
	dimmed1 = "#c4c6cd",
	dimmed2 = "#9b9ea4",
	dimmed3 = "#9b9ea4",
	dimmed4 = "#4f5258",
	dimmed5 = "#2c2e33",
}

---@type Beast.Palette
local cache = vim.deepcopy(defaults)

---@param group string
---@param attr "fg"|"bg"
---@param fallback string
---@return string
local function extract(group, attr, fallback)
	local value = Util.colors.inspect(group)[attr]
	return value or fallback
end

---@return boolean
function M.is_builtin_colorscheme()
	local name = vim.g.colors_name or "default"
	local path = vim.env.VIMRUNTIME .. "/colors/"
	return vim.uv.fs_stat(path .. name .. ".lua") ~= nil or vim.uv.fs_stat(path .. name .. ".vim") ~= nil
end

--- Derive palette from Neovim's named color palette (NvimLight*/NvimDark*).
--- The builtin `default` colorscheme exposes a stable, role-aware palette via
--- these names — use them as the source of truth instead of extracting from
--- syntax groups (which may be unstyled, linked, or re-styled by our own
--- highlight modules, creating feedback loops on refresh).
---@return Beast.Palette
local function extract_builtin()
	local background = extract("Normal", "bg", defaults.background)
	local text = extract("Normal", "fg", defaults.text)
	local blend = Util.colors.blend

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

	local is_dark = vim.o.background == "dark"
	local light = is_dark and "NvimLight" or "NvimDark"

	return {
		dark2 = blend(text, 0.20, background), -- #3d3f44
		dark1 = blend(text, 0.10, background), -- #282a30
		background = background,
		text = text,
		accent1 = named(light .. "Red", defaults.accent1), -- #ffc0b9
		accent2 = named(light .. "Yellow", defaults.accent2), -- #fce094
		accent3 = named(light .. "Green", defaults.accent3), -- #b3f6c0
		accent4 = named(light .. "Cyan", defaults.accent4), -- #8cf8f7
		accent5 = named(light .. "Blue", defaults.accent5), -- #a6dbff
		accent6 = named(light .. "Magenta", defaults.accent6), -- #ffcaff
		dimmed1 = blend(text, 0.75, background), -- #adafb6
		dimmed2 = blend(text, 0.55, background), -- #84868d
		dimmed3 = blend(text, 0.40, background), -- #66686e
		dimmed4 = blend(text, 0.25, background), -- #47494f
		dimmed5 = blend(text, 0.10, background), -- #282a30
	}
end

--- Extraction map for third-party colorschemes with rich highlight definitions.
---@return Beast.Palette
local function extract_custom()
	return {
		dark2 = extract("StatusLine", "bg", defaults.dark2),
		dark1 = extract("TabLineFill", "bg", defaults.dark1),
		background = extract("Normal", "bg", defaults.background),
		text = extract("Normal", "fg", defaults.text),
		accent1 = extract("DiagnosticError", "fg", defaults.accent1),
		accent2 = extract("DiagnosticWarn", "fg", defaults.accent2),
		accent3 = extract("String", "fg", defaults.accent3),
		accent4 = extract("@function", "fg", defaults.accent4),
		accent5 = extract("Structure", "fg", defaults.accent5),
		accent6 = extract("Boolean", "fg", defaults.accent6),
		dimmed1 = extract("NormalFloat", "fg", defaults.dimmed1),
		dimmed2 = extract("FloatBorder", "fg", defaults.dimmed2),
		dimmed3 = extract("Comment", "fg", defaults.dimmed3),
		dimmed4 = extract("LineNr", "fg", defaults.dimmed4),
		dimmed5 = extract("Pmenu", "bg", defaults.dimmed5),
	}
end

--- Re-extract all palette colors from the current colorscheme.
function M.refresh()
	if M.is_builtin_colorscheme() then
		cache = extract_builtin()
		-- Builtin colorschemes often define StatusLine with reverse or light bg
		-- which clashes with dark-themed UI. Override with palette-derived colors.
		vim.api.nvim_set_hl(0, "StatusLine", { fg = cache.text, bg = cache.dark2 })
		vim.api.nvim_set_hl(0, "StatusLineNC", { fg = cache.dimmed3, bg = cache.dark1 })
	else
		cache = extract_custom()
	end
end

--- Get the current palette (read-only snapshot).
---@return Beast.Palette
function M.get()
	return cache
end

function M.setup()
	require("beast").apply_highlights("beast.palette.highlights")
	require("beast").apply_highlights("beast.palette.blink")
end

return M
