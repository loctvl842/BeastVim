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
		name = "mini.pairs",
		src = gh("nvim-mini/mini.pairs"),
		lazy = { event = { "InsertEnter", "CmdlineEnter" } },
		config = function()
			local opts = {
				modes = { insert = true, command = true, terminal = false },
				-- Skip autopair when the next character matches this pattern.
				skip_next = [=[[%w%%%'%[%"%.%`%$]]=],
				-- Skip autopair when the cursor is inside these treesitter captures.
				skip_ts = { "string" },
				-- Skip autopair when next char is the closing pair and the line
				-- already has more closers than openers.
				skip_unbalanced = true,
				-- Expand ``` into a fenced code block in markdown.
				markdown = true,
			}

			local pairs = require("mini.pairs")
			pairs.setup(opts)

			local open = pairs.open
			pairs.open = function(pair, neigh_pattern)
				if vim.fn.getcmdline() ~= "" then
					return open(pair, neigh_pattern)
				end
				local o, c = pair:sub(1, 1), pair:sub(2, 2)
				local line = vim.api.nvim_get_current_line()
				local cursor = vim.api.nvim_win_get_cursor(0)
				local next = line:sub(cursor[2] + 1, cursor[2] + 1)
				local before = line:sub(1, cursor[2])

				if opts.markdown and o == "`" and vim.bo.filetype == "markdown" and before:match("^%s*``") then
					return "`\n```" .. vim.api.nvim_replace_termcodes("<up>", true, true, true)
				end

				if opts.skip_next and next ~= "" and next:match(opts.skip_next) then
					return o
				end

				if opts.skip_ts and #opts.skip_ts > 0 then
					local ok, captures =
						pcall(vim.treesitter.get_captures_at_pos, 0, cursor[1] - 1, math.max(cursor[2] - 1, 0))
					for _, capture in ipairs(ok and captures or {}) do
						if vim.tbl_contains(opts.skip_ts, capture.capture) then
							return o
						end
					end
				end

				if opts.skip_unbalanced and next == c and c ~= o then
					local _, count_open = line:gsub(vim.pesc(o), "")
					local _, count_close = line:gsub(vim.pesc(c), "")
					if count_close > count_open then
						return o
					end
				end

				return open(pair, neigh_pattern)
			end
		end,
	},

	-- Snippet data for the snippets source. Loaded via dependency chain.
	{
		name = "friendly-snippets",
		src = gh("rafamadriz/friendly-snippets"),
	},

	{
		name = "blink.cmp",
		src = gh("saghen/blink.cmp"),
		-- Pin to the v1 release line. v2 (main) requires `saghen/blink.lib`
		-- (which has no tagged releases) and uses a separate download() API.
		version = vim.version.range("1"),
		dependencies = { "friendly-snippets" },
		lazy = { event = { "InsertEnter", "CmdlineEnter" } },
		config = function()
			local function capitalize(s)
				if not s or s == "" then
					return s
				end
				return s:sub(1, 1):upper() .. s:sub(2)
			end

			require("blink.cmp").setup({
				-- Skip BeastVim UI buffers (explorer, key cheatsheet, packer,
				-- confirm, notify, toast, finder, blame view, key hint, etc.).
				-- Their filetypes are all prefixed with `beast-`/`Beast`; we
				-- also tag the explorer rename/create prompt with
				-- `beast-explorer-prompt`. Finder's input uses
				-- `buftype = "prompt"` which blink already skips.
				enabled = function()
					return not vim.bo.filetype:lower():match("^beast")
				end,
				appearance = {
					-- sets the fallback highlight groups to nvim-cmp's highlight groups
					-- useful for when your theme doesn't support blink.cmp
					use_nvim_cmp_as_default = false,
					-- set to 'mono' for 'Nerd Font Mono' or 'normal' for 'Nerd Font'
					-- adjusts spacing to ensure icons are aligned
					nerd_font_variant = "mono",
					kind_icons = Icon.kinds,
				},
				completion = {
					keyword = {
						-- 'prefix' will fuzzy match on the text before the cursor
						-- 'full' will fuzzy match on the text before _and_ after the cursor
						range = "prefix",
					},
					list = {
						selection = {
							preselect = function(ctx)
								return ctx.mode ~= "cmdline"
							end,
							auto_insert = false,
						},
					},
					accept = { auto_brackets = { enabled = false } },
					menu = {
						draw = {
							align_to = "cursor",
							treesitter = { "lsp" },
							columns = {
								{ "kind_icon", "label", "label_description", gap = 1 },
								{ "source_name", gap = 1 },
							},
							components = {
								source_name = {
									ellipsis = false,
									width = { fill = true },
									text = function(ctx)
										if ctx.source_name == "LSP" then
											return ctx.kind
										else
											return capitalize(ctx.source_name)
										end
									end,
								},
								kind_icon = {
									ellipsis = false,
									text = function(ctx)
										local brain_kind = Icon.brain[ctx.source_name]
										if brain_kind then
											local hl_gr = capitalize("BlinkCmpKind" .. capitalize(ctx.source_name))
											vim.api.nvim_set_hl(0, hl_gr, { fg = Icon.colors.brain[ctx.source_name] })
											return brain_kind .. ctx.icon_gap
										end
										return ctx.kind_icon .. ctx.icon_gap
									end,
								},
							},
						},
					},
					documentation = {
						auto_show = true,
						auto_show_delay_ms = 200,
					},
					ghost_text = {
						enabled = true,
					},
				},

				sources = {
					default = { "lsp", "path", "snippets", "buffer" },
				},

				cmdline = {
					enabled = true,
					keymap = {
						["<CR>"] = { "fallback" },
						["<C-y>"] = { "select_and_accept" },
					},
					sources = function()
						local t = vim.fn.getcmdtype()
						-- Forward + backward search → completion from buffer text.
						if t == "/" or t == "?" then
							return { "buffer" }
						end
						-- Ex commands → cmdline source (commands, options, args).
						if t == ":" or t == "@" then
							return { "cmdline" }
						end
						return {}
					end,
					completion = {
						trigger = {
							show_on_blocked_trigger_characters = {},
						},
						menu = {
							auto_show = true,
							draw = {
								columns = { { "kind_icon", "label", "label_description", gap = 1 } },
							},
						},
					},
				},

				keymap = {
					preset = "enter",
					["<C-y>"] = { "select_and_accept" },
				},

				fuzzy = { implementation = "prefer_rust_with_warning" },
			})
		end,
	},
}
