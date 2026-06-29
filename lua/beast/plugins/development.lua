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
				library = {
					{ path = "${3rd}/luv/library", words = { "vim%.uv" } },
					{ path = "snacks.nvim", words = { "Snacks" } },
				},
			})
		end,
	},
	{
		name = "fff.nvim",
		src = gh("dmtrKovalenko/fff"),
		build = function()
			-- downloads a prebuilt binary or falls back to cargo build
			require("fff.download").download_or_build_binary()
		end,
		lazy = {
			keys = {
				{
					"<leader>Tf",
					function()
						require("fff").find_files()
					end,
					desc = "FFFind files",
					group = "fff.nvim",
				},
				{
					"<leader>Tg",
					function()
						require("fff").live_grep()
					end,
					desc = "LiFFFe grep",
					group = "fff.nvim",
				},
				{
					"<leader>Tz",
					function()
						require("fff").live_grep({ grep = { modes = { "fuzzy", "plain" } } })
					end,
					desc = "Live fffuzy grep",
					group = "fff.nvim",
				},
				{
					"<leader>Tw",
					function()
						require("fff").live_grep_under_cursor()
					end,
					mode = { "n", "x" },
					desc = "Search current word / selection",
					group = "fff.nvim",
				},
			},
		},
	},
}
