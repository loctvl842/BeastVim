-- Name:        monokai-pro-ristretto
-- Description: BeastVim local colorscheme - Monokai Pro (ristretto filter)
--              The BeastVim* groups are palette carriers read by
--              beast.theme.sources.beastvim, mirroring Neovim's
--              NvimDark*/NvimLight* named-color convention.

vim.cmd.highlight("clear")
if vim.fn.exists("syntax_on") then
	vim.cmd("syntax reset")
end
vim.o.background = "dark"
vim.g.colors_name = "monokai-pro-ristretto"

local hi = vim.api.nvim_set_hl

-- Rendering
hi(0, "Normal", { fg = "#fff1f3", bg = "#2c2525" })

-- Palette carriers (fg values = Beast.Theme.Palette)
hi(0, "BeastVimDark2", { fg = "#191515" })
hi(0, "BeastVimDark1", { fg = "#211c1c" })
hi(0, "BeastVimBackground", { fg = "#2c2525" })
hi(0, "BeastVimText", { fg = "#fff1f3" })
hi(0, "BeastVimAccent1", { fg = "#fd6883" })
hi(0, "BeastVimAccent2", { fg = "#f38d70" })
hi(0, "BeastVimAccent3", { fg = "#f9cc6c" })
hi(0, "BeastVimAccent4", { fg = "#adda78" })
hi(0, "BeastVimAccent5", { fg = "#85dacc" })
hi(0, "BeastVimAccent6", { fg = "#a8a9eb" })
hi(0, "BeastVimDimmed1", { fg = "#c3b7b8" })
hi(0, "BeastVimDimmed2", { fg = "#948a8b" })
hi(0, "BeastVimDimmed3", { fg = "#72696a" })
hi(0, "BeastVimDimmed4", { fg = "#5b5353" })
hi(0, "BeastVimDimmed5", { fg = "#403838" })
