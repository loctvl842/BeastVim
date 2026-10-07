-- Name:        monokai-pro-light
-- Description: BeastVim local colorscheme - Monokai Pro (light filter)
--              The BeastVim* groups are palette carriers read by
--              beast.theme.sources.beastvim, mirroring Neovim's
--              NvimDark*/NvimLight* named-color convention.

vim.cmd.highlight("clear")
if vim.fn.exists("syntax_on") then
	vim.cmd("syntax reset")
end
vim.o.background = "light"
vim.g.colors_name = "monokai-pro-light"

local hi = vim.api.nvim_set_hl

-- Rendering
hi(0, "Normal", { fg = "#29242a", bg = "#faf4f2" })

-- Palette carriers (fg values = Beast.Theme.Palette)
hi(0, "BeastVimDark2", { fg = "#d3cdcc" })
hi(0, "BeastVimDark1", { fg = "#ede7e5" })
hi(0, "BeastVimBackground", { fg = "#faf4f2" })
hi(0, "BeastVimText", { fg = "#29242a" })
hi(0, "BeastVimAccent1", { fg = "#e14775" })
hi(0, "BeastVimAccent2", { fg = "#e16032" })
hi(0, "BeastVimAccent3", { fg = "#cc7a0a" })
hi(0, "BeastVimAccent4", { fg = "#269d69" })
hi(0, "BeastVimAccent5", { fg = "#1c8ca8" })
hi(0, "BeastVimAccent6", { fg = "#7058be" })
hi(0, "BeastVimDimmed1", { fg = "#706b6e" })
hi(0, "BeastVimDimmed2", { fg = "#918c8e" })
hi(0, "BeastVimDimmed3", { fg = "#a59fa0" })
hi(0, "BeastVimDimmed4", { fg = "#bfb9ba" })
hi(0, "BeastVimDimmed5", { fg = "#d3cdcc" })
