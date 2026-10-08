---@type Beast.Packer.PluginSpec[]
return {
	{
		name = "supermaven-nvim",
		src = gh("supermaven-inc/supermaven-nvim"),
		lazy = {
			cmd = {
				"SupermavenUseFree",
				"SupermavenUsePro",
			},
			event = { "InsertEnter" },
		},
		cond = function()
			local fsize = vim.fn.getfsize(vim.fn.expand("%"))
			-- Only load the plugin if the file is less than 5 MB
			return fsize < (5 * 1024 * 1024)
		end,
		dependencies = { "blink.cmp", "blink-cmp-supermaven" },
		config = function()
			require("supermaven-nvim").setup({
				keymaps = {
					accept_suggestion = "<C-o>",
				},
				ignore_filetypes = { "snacks_input", "snacks_notif" },
			})

			-- Register the blink.cmp source lazily, now that supermaven is loaded.
			require("blink.cmp").add_source_provider("supermaven", {
				name = "supermaven", -- compat name
				score_offset = 300,
				module = "blink-cmp-supermaven",
				async = true,
			})
			table.insert(require("blink.cmp.config").sources.default, "supermaven")
		end,
	},
	{
		name = "blink-cmp-supermaven",
		src = gh("huijiro/blink-cmp-supermaven"),
	},
}
