-- Name:        monokai-pro-octagon
-- Description: BeastVim local colorscheme - Monokai Pro (octagon filter)
--              The BeastVim* groups are palette carriers read by
--              beast.theme.sources.beastvim, mirroring Neovim's
--              NvimDark*/NvimLight* named-color convention.

vim.cmd.highlight("clear")
if vim.fn.exists("syntax_on") then
	vim.cmd("syntax reset")
end
vim.o.background = "dark"
vim.g.colors_name = "monokai-pro-octagon"

local hi = vim.api.nvim_set_hl

-- Rendering
hi(0, "Normal", { fg = "#eaf2f1", bg = "#282a3a" })

-- Palette carriers (fg values = Beast.Theme.Palette)
hi(0, "BeastVimDark2", { fg = "#161821" })
hi(0, "BeastVimDark1", { fg = "#1e1f2b" })
hi(0, "BeastVimBackground", { fg = "#282a3a" })
hi(0, "BeastVimText", { fg = "#eaf2f1" })
hi(0, "BeastVimAccent1", { fg = "#ff657a" })
hi(0, "BeastVimAccent2", { fg = "#ff9b5e" })
hi(0, "BeastVimAccent3", { fg = "#ffd76d" })
hi(0, "BeastVimAccent4", { fg = "#bad761" })
hi(0, "BeastVimAccent5", { fg = "#9cd1bb" })
hi(0, "BeastVimAccent6", { fg = "#c39ac9" })
hi(0, "BeastVimDimmed1", { fg = "#b2b9bd" })
hi(0, "BeastVimDimmed2", { fg = "#888d94" })
hi(0, "BeastVimDimmed3", { fg = "#696d77" })
hi(0, "BeastVimDimmed4", { fg = "#535763" })
hi(0, "BeastVimDimmed5", { fg = "#3a3d4b" })
