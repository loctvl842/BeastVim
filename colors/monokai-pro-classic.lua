-- Name:        monokai-pro-classic
-- Description: BeastVim local colorscheme - Monokai Pro (classic filter)
--              The BeastVim* groups are palette carriers read by
--              beast.theme.sources.beastvim, mirroring Neovim's
--              NvimDark*/NvimLight* named-color convention.

vim.cmd.highlight("clear")
if vim.fn.exists("syntax_on") then
	vim.cmd("syntax reset")
end
vim.o.background = "dark"
vim.g.colors_name = "monokai-pro-classic"

local hi = vim.api.nvim_set_hl

-- Rendering
hi(0, "Normal", { fg = "#fdfff1", bg = "#272822" })

-- Palette carriers (fg values = Beast.Theme.Palette)
hi(0, "BeastVimDark2", { fg = "#161613" })
hi(0, "BeastVimDark1", { fg = "#1d1e19" })
hi(0, "BeastVimBackground", { fg = "#272822" })
hi(0, "BeastVimText", { fg = "#fdfff1" })
hi(0, "BeastVimAccent1", { fg = "#f92672" })
hi(0, "BeastVimAccent2", { fg = "#fd971f" })
hi(0, "BeastVimAccent3", { fg = "#e6db74" })
hi(0, "BeastVimAccent4", { fg = "#a6e22e" })
hi(0, "BeastVimAccent5", { fg = "#66d9ef" })
hi(0, "BeastVimAccent6", { fg = "#ae81ff" })
hi(0, "BeastVimDimmed1", { fg = "#c0c1b5" })
hi(0, "BeastVimDimmed2", { fg = "#919288" })
hi(0, "BeastVimDimmed3", { fg = "#6e7066" })
hi(0, "BeastVimDimmed4", { fg = "#57584f" })
hi(0, "BeastVimDimmed5", { fg = "#3b3c35" })
