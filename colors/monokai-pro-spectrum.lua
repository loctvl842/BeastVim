-- Name:        monokai-pro-spectrum
-- Description: BeastVim local colorscheme - Monokai Pro (spectrum filter)
--              The BeastVim* groups are palette carriers read by
--              beast.theme.sources.beastvim, mirroring Neovim's
--              NvimDark*/NvimLight* named-color convention.

vim.cmd.highlight("clear")
if vim.fn.exists("syntax_on") then
	vim.cmd("syntax reset")
end
vim.o.background = "dark"
vim.g.colors_name = "monokai-pro-spectrum"

local hi = vim.api.nvim_set_hl

-- Rendering
hi(0, "Normal", { fg = "#f7f1ff", bg = "#222222" })

-- Palette carriers (fg values = Beast.Theme.Palette)
hi(0, "BeastVimDark2", { fg = "#131313" })
hi(0, "BeastVimDark1", { fg = "#191919" })
hi(0, "BeastVimBackground", { fg = "#222222" })
hi(0, "BeastVimText", { fg = "#f7f1ff" })
hi(0, "BeastVimAccent1", { fg = "#fc618d" })
hi(0, "BeastVimAccent2", { fg = "#fd9353" })
hi(0, "BeastVimAccent3", { fg = "#fce566" })
hi(0, "BeastVimAccent4", { fg = "#7bd88f" })
hi(0, "BeastVimAccent5", { fg = "#5ad4e6" })
hi(0, "BeastVimAccent6", { fg = "#948ae3" })
hi(0, "BeastVimDimmed1", { fg = "#bab6c0" })
hi(0, "BeastVimDimmed2", { fg = "#8b888f" })
hi(0, "BeastVimDimmed3", { fg = "#69676c" })
hi(0, "BeastVimDimmed4", { fg = "#525053" })
hi(0, "BeastVimDimmed5", { fg = "#363537" })
