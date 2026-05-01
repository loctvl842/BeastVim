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
	dark2 = "#1a1a1a",
	dark1 = "#222222",
	background = "#282828",
	text = "#d4d4d4",
	accent1 = "#f44747",
	accent2 = "#ff8800",
	accent3 = "#ffcc00",
	accent4 = "#6a9955",
	accent5 = "#4ec9b0",
	accent6 = "#c586c0",
	dimmed1 = "#cccccc",
	dimmed2 = "#aaaaaa",
	dimmed3 = "#808080",
	dimmed4 = "#555555",
	dimmed5 = "#333333",
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

--- Re-extract all palette colors from the current colorscheme.
function M.refresh()
	cache = {
		dark2 = extract("StatusLine", "bg", defaults.dark2),
		dark1 = extract("TabLineFill", "bg", defaults.dark1),
		background = extract("Normal", "bg", defaults.background),
		text = extract("Normal", "fg", defaults.text),
		accent1 = extract("DiagnosticError", "fg", defaults.accent1),
		accent2 = extract("DiagnosticWarn", "fg", defaults.accent2),
		accent3 = extract("String", "fg", defaults.accent3),
		accent4 = extract("DiagnosticOk", "fg", defaults.accent4),
		accent5 = extract("Structure", "fg", defaults.accent5),
		accent6 = extract("Boolean", "fg", defaults.accent6),
		dimmed1 = extract("NormalFloat", "fg", defaults.dimmed1),
		dimmed2 = extract("FloatBorder", "fg", defaults.dimmed2),
		dimmed3 = extract("Comment", "fg", defaults.dimmed3),
		dimmed4 = extract("LineNr", "fg", defaults.dimmed4),
		dimmed5 = extract("Pmenu", "bg", defaults.dimmed5),
	}
end

--- Get the current palette (read-only snapshot).
---@return Beast.Palette
function M.get()
	return cache
end

return M
