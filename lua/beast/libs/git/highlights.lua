-- Beast.Git highlight definitions.
-- Re-executed on every ColorScheme change via M.highlight_modules.
--
-- All groups link to existing colorscheme groups by default — the BeastVim
-- colorscheme defines GitSignsAdd / Change / Delete regardless of whether
-- gitsigns.nvim is installed.

Util.colors.set_hl("BeastGit", {
	Add = { link = "GitSignsAdd" },
	Change = { link = "GitSignsChange" },
	Delete = { link = "GitSignsDelete" },
	TopDelete = { link = "GitSignsDelete" },
	Changedelete = { link = "GitSignsChange" },
})
