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

--- Pick the first candidate whose fg/bg is defined and differs from `exclude`.
---@param candidates string[] Highlight group names
---@param attr "fg"|"bg"
---@param exclude? string Hex color to skip (e.g. Normal fg to avoid indistinct accents)
---@param fallback string
---@return string
local function first_distinct(candidates, attr, exclude, fallback)
	for _, group in ipairs(candidates) do
		local value = Util.colors.inspect(group)[attr]
		if value and value ~= exclude then
			return value
		end
	end
	return fallback
end

---@return boolean
---@return boolean
function M.is_builtin_colorscheme()
	local name = vim.g.colors_name or "default"
	local path = vim.env.VIMRUNTIME .. "/colors/"
	return vim.uv.fs_stat(path .. name .. ".lua") ~= nil or vim.uv.fs_stat(path .. name .. ".vim") ~= nil
end

--- Derive palette from Normal bg/fg for builtin colorschemes.
--- Scale colors (darks, dimmeds) are computed via blend so they work
--- regardless of how the colorscheme styles StatusLine, NormalFloat, etc.
--- Accents use a fallback chain that skips groups equal to Normal fg.
---@return Beast.Palette
local function extract_builtin()
	local background = extract("Normal", "bg", defaults.background)
	local text = extract("Normal", "fg", defaults.text)
	local blend = Util.colors.blend

	return {
		dark2 = blend(text, 0.20, background),
		dark1 = blend(text, 0.10, background),
		background = background,
		text = text,
		accent1 = first_distinct({ "Constant", "Boolean" }, "fg", text, defaults.accent1),
		accent2 = first_distinct({ "PreProc", "StorageClass" }, "fg", text, defaults.accent2),
		accent3 = extract("String", "fg", defaults.accent3),
		accent4 = first_distinct({ "Function", "Identifier" }, "fg", text, defaults.accent4),
		accent5 = first_distinct({ "Structure", "Type", "Keyword" }, "fg", text, defaults.accent5),
		accent6 = first_distinct({ "Boolean", "Constant", "Special" }, "fg", text, defaults.accent6),
		dimmed1 = blend(text, 0.75, background),
		dimmed2 = blend(text, 0.55, background),
		dimmed3 = blend(text, 0.40, background),
		dimmed4 = blend(text, 0.25, background),
		dimmed5 = blend(text, 0.10, background),
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

return M
