---@type Beast.Packer.PluginSpec[]
return {
	{
		name = "lazydev.nvim",
		src = gh("folke/lazydev.nvim"),
		lazy = {
			filetype = "lua",
			cmd = "LazyDev",
		},
		config = function()
			require("lazydev").setup({
				-- Workspaces with their own .luarc.json (BeastVim) configure lua_ls themselves; lazydev's
				-- pathStrict + ignoreDir "/lua" overrides leave every `require("beast.*")` unresolved.
				enabled = function(root_dir)
					return not vim.uv.fs_stat(root_dir .. "/.luarc.json")
				end,
				library = {
					{ path = "${3rd}/luv/library", words = { "vim%.uv" } },
					{ path = "snacks.nvim", words = { "Snacks" } },
				},
			})
		end,
	},
}
