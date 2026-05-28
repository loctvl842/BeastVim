return {
	{ import = "beast.plugins.colorscheme" },
	{
		name = "nvim-web-devicons",
		src = gh("nvim-tree/nvim-web-devicons"),
		lazy = {
			-- Load only when someone requires the module or a dependent plugin needs it
			module = "nvim-web-devicons",
		},
	},
}
