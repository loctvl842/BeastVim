---@type Beast.Packer.PluginSpec[]
return {
	{
		name = "monokai-pro.nvim",
		src = gh("loctvl842/monokai-pro.nvim"),
		-- Defer full theme initialization until UI is ready to reduce startup cost
		-- lazy = { event = "UIEnter" },
		lazy = nil,
		config = function()
			local mp = require("monokai-pro")
			mp.setup({
				transparent_background = false,
				-- Avoid forcing devicons integration at startup; it will activate when devicons loads
				devicons = true,
				-- Apply core first, then lazily apply plugin integrations
				lazy_integrations = true,
				-- Align integration detection with BeastVim's plugin set
				integration_detectors = {
					indent_blankline = { modules = { "ibl", "indent_blankline" } },
					gitsign = { modules = { "gitsigns" } },
					blink = { modules = { "blink.cmp", "blink" } },
				},
				filter = "pro", -- classic | octagon | pro | machine | ristretto | spectrum
				day_night = {
					enable = false,
					day_filter = "pro",
					night_filter = "spectrum",
				},
				inc_search = "background", -- underline | background
				plugins = {
					bufferline = {
						underline_selected = true,
						underline_visible = false,
						underline_fill = true,
						bold = false,
					},
					indent_blankline = {
						context_highlight = "pro", -- default | pro
						context_start_underline = true,
					},
				},
				override = function(c)
					return {
						DashboardRecent = { fg = c.base.magenta },
						DashboardProject = { fg = c.base.blue },
						DashboardConfiguration = { fg = c.base.white },
						DashboardSession = { fg = c.base.green },
						DashboardLazy = { fg = c.base.cyan },
						DashboardServer = { fg = c.base.yellow },
						DashboardQuit = { fg = c.base.red },
						IndentBlanklineChar = { fg = c.base.dimmed4 },
						NeoTreeStatusLine = { link = "StatusLine" },
						-- indent blankline
						RainbowDelimiterRed = { fg = c.base.red },
						RainbowDelimiterYellow = { fg = c.base.yellow },
						RainbowDelimiterBlue = { fg = c.base.cyan },
						RainbowDelimiterOrange = { fg = c.base.blue },
						RainbowDelimiterGreen = { fg = c.base.green },
						RainbowDelimiterViolet = { fg = c.base.magenta },
						RainbowDelimiterCyan = { fg = c.base.cyan },
						-- mini.hipatterns
						MiniHipatternsFixme = { fg = c.base.black, bg = c.base.red, bold = true },
						MiniHipatternsTodo = { fg = c.base.black, bg = c.base.blue, bold = true },
						MiniHipatternsHack = { fg = c.base.black, bg = c.base.yellow, bold = true },
						MiniHipatternsNote = { fg = c.base.black, bg = c.base.green, bold = true },
						MiniHipatternsWip = { fg = c.base.black, bg = c.base.cyan, bold = true },
					}
				end,
			})
			mp.load()
		end,
	},
	{
		name = "tokyonight.nvim",
		-- lazy = nil,
		lazy = { event = "UIEnter" },
		src = gh("folke/tokyonight.nvim"),
		config = function()
			require("tokyonight").setup()
		end,
	},
}
