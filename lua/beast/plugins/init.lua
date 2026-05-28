return {
	{ import = "beast.plugins.colorscheme" },
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
}
