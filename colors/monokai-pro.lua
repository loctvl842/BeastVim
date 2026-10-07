-- Name:        monokai-pro
-- Description: BeastVim local colorscheme - Monokai Pro (pro filter)
--              The BeastVim* groups are palette carriers read by
--              beast.theme.sources.beastvim, mirroring Neovim's
--              NvimDark*/NvimLight* named-color convention.

vim.cmd.highlight("clear")
if vim.fn.exists("syntax_on") then
	vim.cmd("syntax reset")
end
vim.o.background = "dark"
vim.g.colors_name = "monokai-pro"

local hi = vim.api.nvim_set_hl

-- Rendering
hi(0, "Normal", { fg = "#fcfcfa", bg = "#2d2a2e" })

-- Palette carriers (fg values = Beast.Theme.Palette)
hi(0, "BeastVimDark2", { fg = "#19181a" })
hi(0, "BeastVimDark1", { fg = "#221f22" })
hi(0, "BeastVimBackground", { fg = "#2d2a2e" })
hi(0, "BeastVimText", { fg = "#fcfcfa" })
hi(0, "BeastVimAccent1", { fg = "#ff6188" })
hi(0, "BeastVimAccent2", { fg = "#fc9867" })
hi(0, "BeastVimAccent3", { fg = "#ffd866" })
hi(0, "BeastVimAccent4", { fg = "#a9dc76" })
hi(0, "BeastVimAccent5", { fg = "#78dce8" })
hi(0, "BeastVimAccent6", { fg = "#ab9df2" })
hi(0, "BeastVimDimmed1", { fg = "#c1c0c0" })
hi(0, "BeastVimDimmed2", { fg = "#939293" })
hi(0, "BeastVimDimmed3", { fg = "#727072" })
hi(0, "BeastVimDimmed4", { fg = "#5b595c" })
hi(0, "BeastVimDimmed5", { fg = "#403e41" })
