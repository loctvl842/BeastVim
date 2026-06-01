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
	{
		name = "which-key.nvim",
		src = gh("folke/which-key.nvim"),
		lazy = {
			event = "VimEnter", -- avoid VeryLazy; load after UI starts
		},
		init = function()
			-- reactively update which-key when keys change
			vim.api.nvim_create_autocmd("User", {
				pattern = "BeastKeysChanged",
				callback = function(args)
					local ok, wk = pcall(require, "which-key")
					if not ok then
						return
					end
					local data = args and args.data or {}
					local action = data.action
					local keymap = data.keys
					if action == "keymap:del" then
						-- On deletion, resync the whole spec to avoid stale entries
						pcall(wk.add, Key.to_which_key())
					elseif keymap then
						-- Incrementally add/refresh the changed item
						local spec = Key.to_which_key_spec(keymap)
						pcall(wk.add, { spec })
					else
						-- Fallback: resync everything
						pcall(wk.add, Key.to_which_key())
					end
				end,
			})
		end,
		config = function()
			local ok, wk = pcall(require, "which-key")
			if not ok then
				return
			end

			-- minimal setup; users can override via their own config
			wk.setup({
				plugins = {
					spelling = { enabled = true },
					presets = { operators = false, motions = false },
				},
				delay = function(ctx)
					return ctx.plugin and 0 or 50
				end,
				win = {
					padding = { 1, 2 }, -- extra window padding [top/bottom, right/left]
					wo = { winblend = 10 },
				},
				layout = {
					height = { min = 3, max = 25 }, -- min and max height of the columns
					width = { min = 20, max = 100 }, -- min and max width of the columns
					spacing = 5, -- spacing between columns
					align = "center", -- align columns left, center or right
				},
				sort = { "group", "alphanum" },
				icons = {
					mappings = true,
					rules = {
						{ pattern = "dashboard", icon = "🦁", color = "red" },
						{ pattern = "find", icon = " ", color = "cyan" },
						{ pattern = "close", icon = "󰅙", color = "red" },
						{ pattern = "monokai", icon = "", color = "yellow" },
						{ pattern = "explorer", icon = "󱏒", color = "green" },
						{ pattern = "format and save", icon = "󱣪", color = "green" },
						{ pattern = "save", icon = "󰆓", color = "green" },
						{ pattern = "zoom", icon = "", color = "gray" },
						{ pattern = "split.*vertical", icon = "󰤼", color = "gray" },
						{ pattern = "split.*horizontal", icon = "󰤻", color = "gray" },
						{ pattern = "lsp", icon = "󰒋", color = "cyan" },
						{ pattern = "chatgpt", icon = "󰚩", color = "azure" },
						{ pattern = "markdown", icon = "", color = "green" },
						{ pattern = "diagnostic", icon = "", color = "red" },
						{ pattern = "definition", icon = "󰇀", color = "purple" },
						{ pattern = "implement", icon = "󰳽", color = "purple" },
						{ pattern = "reference", icon = "󰆽", color = "purple" },
						-- Group [<leader>h]
						{ pattern = "blame", icon = "", color = "yellow" },
						{ pattern = "diff", icon = "", color = "green" },
						{ pattern = "hunk change", icon = "", color = "yellow" },
						{ pattern = "reset", icon = "", color = "gray" },
						{ pattern = "stage", icon = "", color = "green" },
						{ pattern = "undo", icon = "", color = "gray" },
						{ pattern = "hunk", icon = "󰊢", color = "red" },
						{ pattern = "branch", icon = "", color = "red" },
						{ pattern = "commit", icon = "", color = "green" },
						-- Group [g]
						{ pattern = "word", icon = "", color = "gray" },
						{ pattern = "first line", icon = "", color = "gray" },
						{ pattern = "comment", icon = "󰅺", color = "cyan" },
						{ pattern = "cycle backwards", icon = "󰾹", color = "gray" },
						{ pattern = "selection", icon = "󰒉", color = "gray" },
						-- Group [<leader>hn]
						{ pattern = "annotation", icon = "󰙆", color = "cyan" },
					},
				},
				defaults = {},
				spec = {
					mode = { "n", "v" },
					{ "<leader>g", group = "+Git" },
					{ "f", group = "+Fold" },
					{ "g", group = "+Goto" },
					{ "s", group = "+Search" },
				},
				triggers = {
					{ "<leader>", mode = { "n", "v" } },
					{ "[", group = "prev" },
					{ "]", group = "next" },
					{ "f", mode = { "n" } }, -- fold group
					{ "g", mode = { "n", "v" } }, -- search group
				},
			})
		end,
	},
}
