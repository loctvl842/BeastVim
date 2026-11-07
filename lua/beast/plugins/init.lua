---@type Beast.Packer.PluginSpec[]
return {
	{ import = "beast.plugins.colorscheme" },
	{ import = "beast.plugins.development" },
	{ import = "beast.plugins.lang" },
	{ import = "beast.plugins.coding" },
	{
		name = "nvim-web-devicons",
		src = gh("nvim-tree/nvim-web-devicons"),
		lazy = {
			module = "nvim-web-devicons",
		},
	},
	{
		name = "mini.icons",
		src = gh("nvim-mini/mini.icons"),
		lazy = {
			module = "mini.icons",
		},
		config = function()
			require("mini.icons").setup({})
		end,
	},

	-- Snippet data for the snippets source. Loaded via dependency chain.
	{
		name = "friendly-snippets",
		src = gh("rafamadriz/friendly-snippets"),
	},

	{
		name = "markview.nvim",
		src = gh("OXY2DEV/markview.nvim"),
		dependencies = { "beast.theme" },
		lazy = {
			filetype = { "markdown" },
			dependencies = { "nvim-tree/nvim-web-devicons" },
		},
		config = function()
			require("markview").setup({
				preview = { icon_provider = "mini" },
			})
		end,
	},
}
