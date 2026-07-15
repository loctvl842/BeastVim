-- Disable built-in rtp plugins we don't use. Must run BEFORE Neovim sources
-- $VIMRUNTIME/plugin/*.vim (i.e. before any require() that triggers init), so
-- the guard `if exists("loaded_<name>")` short-circuits each script.
-- See docs/development/benchmarking.md for the why.
vim.g.loaded_gzip = 1
vim.g.loaded_tarPlugin = 1
vim.g.loaded_zipPlugin = 1
vim.g.loaded_tohtml = 1
vim.g.loaded_tutor = 1
-- netrw: replaced by beast.libs.explorer (neo-tree backend)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

if os.getenv("BEAST_PROFILE") == "1" then
	pcall(function()
		local profile = require("beast.profile")
		profile.start()
		local out = os.getenv("BEAST_PROFILE_OUT") or (vim.fn.stdpath("cache") .. "/beast-profile.txt")
		profile.auto_dump_on_quit(out)
	end)
end

require("beast").setup({
	key = {
		hint = { triggers = { "<leader>", "<localleader>", "f", "z", "g", "[", "]" } },
		mappings = {
			{ "fd", "zd", desc = "Delete fold under cursor" },
			{ "fo", "zo", desc = "Open fold under cursor" },
			{ "fO", "zO", desc = "Open all folds under cursor" },
			{ "fc", "zC", desc = "Close all folds under cursor" },
			{ "fa", "za", desc = "Toggle fold under cursor" },
			{ "fA", "zA", desc = "Toggle all folds under cursor" },
			{ "fv", "zv", desc = "Show cursor line" },
			{ "fM", "zM", desc = "Close all folds" },
			{ "fR", "zR", desc = "Open all folds" },
			{ "fm", "zm", desc = "Fold more" },
			{ "fr", "zr", desc = "Fold less" },
			{ "fx", "zx", desc = "Update folds" },
			{ "fz", "zz", desc = "Center this line" },
			{ "ft", "zt", desc = "Top this line" },
			{ "fb", "zb", desc = "Bottom this line" },
			{ "fg", "zg", desc = "Add word to spell list" },
			{ "fw", "zw", desc = "Mark word as bad/misspelling" },
			{ "fe", "ze", desc = "Right this line" },
			{ "fE", "zE", desc = "Delete all folds in current buffer" },
			{ "fs", "zs", desc = "Left this line" },
			{ "fH", "zH", desc = "Half screen to the left" },
			{ "fL", "zL", desc = "Half screen to the right" },
		},
	},
	explorer = {
		icon = {
			dir_open = "󰝰", -- nf-md-folder_open
			dir_closed = "󰉋", -- nf-md-folder
			-- git = {
			-- 	conflict = "󰞇",
			-- 	modified = "●",
			-- 	renamed = "󰁕",
			-- 	copied = "⧉",
			-- 	deleted = "󰍵",
			-- 	added = "󰐕",
			-- 	untracked = "󰞋",
			-- 	ignored = "󰈉",
			-- },
		},
		mappings = {
			["l"] = "open",
		},
	},
	packer = {
		spec = { { import = "beast.plugins" } },
	},
	treesitter = {
		ensure_installed = {
			"python",
			"lua",
			"javascript",
			"typescript",
			{ "tsx", "typescriptreact" },
			"json",
			"css",
			"html",
		},
		fold = { enable = true },
	},
})

-- ---------------------------------------------------------------------------
-- LSP wiring (hardcoded until BeastVim/<Lang> extension repos exist).
-- ---------------------------------------------------------------------------

-- blink.cmp client capabilities → contributed lazily (forces blink.cmp load
-- only when capabilities are first resolved, i.e. on the first Lsp.register).
Lsp.add_capabilities(function()
	local ok, blink = pcall(require, "blink.cmp")
	if not ok then
		return {}
	end
	return blink.get_lsp_capabilities(nil, false)
end)

Lsp.register("lua_ls", {
	cmd = { "lua-language-server" },
	filetypes = { "lua" },
	root_markers = { ".luarc.json", ".luarc.jsonc", ".git" },
	settings = {
		Lua = {
			workspace = { checkThirdParty = false },
			telemetry = { enable = false },
			diagnostics = { globals = { "vim" } },
			completion = { callSnippet = "Replace" },
		},
	},
	keys = {
		{ "K", vim.lsp.buf.hover, desc = "Hover", cond = "textDocument/hover" },
		-- { "gd", vim.lsp.buf.definition, desc = "Go to definition", cond = "textDocument/definition" },
		-- { "gD", vim.lsp.buf.declaration, desc = "Go to declaration", cond = "textDocument/declaration" },
		-- { "gr", vim.lsp.buf.references, desc = "References", cond = "textDocument/references" },
		-- { "gi", vim.lsp.buf.implementation, desc = "Implementation", cond = "textDocument/implementation" },
		{ "<leader>rn", vim.lsp.buf.rename, desc = "Rename", cond = "textDocument/rename" },
		{
			"<leader>la",
			vim.lsp.buf.code_action,
			mode = { "n", "v" },
			desc = "Code action",
			cond = "textDocument/codeAction",
		},
	},
})
