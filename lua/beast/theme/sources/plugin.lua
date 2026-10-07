--- Third-party colorschemes with rich highlight definitions. Fallback source:
--- samples the palette from well-known highlight groups.
local palette = require("beast.theme.palette")

---@type Beast.Theme.Source
local M = { name = "plugin" }

---@return boolean
function M.matches()
	return true
end

---@return Beast.Theme.Palette
function M.extract()
	return palette.from_groups({
		dark2 = { "StatusLine", "bg" },
		dark1 = { "TabLineFill", "bg" },
		background = { "Normal", "bg" },
		text = { "Normal", "fg" },
		accent1 = { "DiagnosticError", "fg" },
		accent2 = { "DiagnosticWarn", "fg" },
		accent3 = { "String", "fg" },
		accent4 = { "@function", "fg" },
		accent5 = { "Structure", "fg" },
		accent6 = { "Boolean", "fg" },
		dimmed1 = { "NormalFloat", "fg" },
		dimmed2 = { "FloatBorder", "fg" },
		dimmed3 = { "Comment", "fg" },
		dimmed4 = { "LineNr", "fg" },
		dimmed5 = { "Pmenu", "bg" },
	})
end

return M
