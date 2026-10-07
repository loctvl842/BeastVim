-- Name:        monokai-pro-machine
-- Description: BeastVim local colorscheme - Monokai Pro (machine filter)
--              The BeastVim* groups are palette carriers read by
--              beast.theme.sources.beastvim, mirroring Neovim's
--              NvimDark*/NvimLight* named-color convention.

vim.cmd.highlight("clear")
if vim.fn.exists("syntax_on") then
	vim.cmd("syntax reset")
end
vim.o.background = "dark"
vim.g.colors_name = "monokai-pro-machine"

local hi = vim.api.nvim_set_hl

-- Rendering
hi(0, "Normal", { fg = "#f2fffc", bg = "#273136" })

-- Palette carriers (fg values = Beast.Theme.Palette)
hi(0, "BeastVimDark2", { fg = "#161b1e" })
hi(0, "BeastVimDark1", { fg = "#1d2528" })
hi(0, "BeastVimBackground", { fg = "#273136" })
hi(0, "BeastVimText", { fg = "#f2fffc" })
hi(0, "BeastVimAccent1", { fg = "#ff6d7e" })
hi(0, "BeastVimAccent2", { fg = "#ffb270" })
hi(0, "BeastVimAccent3", { fg = "#ffed72" })
hi(0, "BeastVimAccent4", { fg = "#a2e57b" })
hi(0, "BeastVimAccent5", { fg = "#7cd5f1" })
hi(0, "BeastVimAccent6", { fg = "#baa0f8" })
hi(0, "BeastVimDimmed1", { fg = "#b8c4c3" })
hi(0, "BeastVimDimmed2", { fg = "#8b9798" })
hi(0, "BeastVimDimmed3", { fg = "#6b7678" })
hi(0, "BeastVimDimmed4", { fg = "#545f62" })
hi(0, "BeastVimDimmed5", { fg = "#3a4449" })
