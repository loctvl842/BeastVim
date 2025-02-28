local Icons = require("beastvim.tweaks").icons
local Logos = require("beastvim.tweaks").logos

return {
  -- UI components
  { "MunifTanjim/nui.nvim", lazy = true },

  -- icons
  { "nvim-tree/nvim-web-devicons", lazy = true },

  -- Statusline
  {
    "rebelot/heirline.nvim",
    event = { "BufReadPost", "BufNewFile", "BufWritePre" },
    -- lazy = true,
    opts = function()
      local monokai_opts = Utils.plugin.opts("monokai-pro.nvim")
      return {
        float = vim.tbl_contains(monokai_opts.background_clear or {}, "neo-tree"),
        colorful = true,
      }
    end,
    config = function(_, opts)
      local heirline = require("beastvim.features.heirline")
      heirline.setup(opts)
      heirline.load()
    end,
  },

  {
    "akinsho/bufferline.nvim",
    event = { "BufReadPost", "BufNewFile" },
    keys = {
      { "<C-1>", "<Cmd>BufferLineGoToBuffer 1<CR>", desc = "Go to buffer 1" },
      { "<C-2>", "<Cmd>BufferLineGoToBuffer 2<CR>", desc = "Go to buffer 2" },
      { "<C-3>", "<Cmd>BufferLineGoToBuffer 3<CR>", desc = "Go to buffer 3" },
      { "<C-4>", "<Cmd>BufferLineGoToBuffer 4<CR>", desc = "Go to buffer 4" },
      { "<C-5>", "<Cmd>BufferLineGoToBuffer 5<CR>", desc = "Go to buffer 5" },
      { "<C-6>", "<Cmd>BufferLineGoToBuffer 6<CR>", desc = "Go to buffer 6" },
      { "<C-7>", "<Cmd>BufferLineGoToBuffer 7<CR>", desc = "Go to buffer 7" },
      { "<C-8>", "<Cmd>BufferLineGoToBuffer 8<CR>", desc = "Go to buffer 8" },
      { "<C-9>", "<Cmd>BufferLineGoToBuffer 9<CR>", desc = "Go to buffer 9" },
      { "<S-l>", "<Cmd>BufferLineCycleNext<CR>", desc = "Next buffer" },
      { "<S-h>", "<Cmd>BufferLineCyclePrev<CR>", desc = "Previous buffer" },
      { "<A-S-l>", "<Cmd>BufferLineMoveNext<CR>", desc = "Move buffer right" },
      { "<A-S-h>", "<Cmd>BufferLineMovePrev<CR>", desc = "Move buffer left" },
    },
    opts = function()
      local monokai_opts = Utils.plugin.opts("monokai-pro.nvim")
      return {
        options = {
          diagnostics = "nvim_lsp", -- | "nvim_lsp" | "coc",
          -- separator_style = "", -- | "thick" | "thin" | "slope" | { 'any', 'any' },
          separator_style = { "", "" }, -- | "thick" | "thin" | { 'any', 'any' },
          -- separator_style = "slant", -- | "thick" | "thin" | { 'any', 'any' },
          indicator = {
            -- icon = " ",
            -- style = 'icon',
            style = "underline",
          },
          close_command = "Bdelete! %d", -- can be a string | function, see "Mouse actions"
          diagnostics_indicator = function(count, _, _, _)
            if count > 9 then
              return "9+"
            end
            return tostring(count)
          end,
          offsets = {
            {
              filetype = "neo-tree",
              text = "EXPLORER",
              text_align = "center",
              separator = vim.tbl_contains(monokai_opts.background_clear or {}, "neo-tree"), -- set to `true` if clear background of neo-tree
            },
            {
              filetype = "NvimTree",
              text = "EXPLORER",
              text_align = "center",
              separator = vim.tbl_contains(monokai_opts.background_clear or {}, "nvim-tree"), -- set to `true` if clear background of neo-tree
            },
          },
          hover = {
            enabled = true,
            delay = 0,
            reveal = { "close" },
          },
        },
      }
    end,
  },

  -- [Possible Deprecated]
  {
    "utilyre/barbecue.nvim",
    event = { "BufReadPost", "BufNewFile", "BufWritePre" },
    dependencies = {
      "SmiteshP/nvim-navic",
      "nvim-tree/nvim-web-devicons",
    },
    opts = {
      attach_navic = false,
      theme = "auto",
      include_buftypes = { "" },
      exclude_filetypes = { "gitcommit", "Trouble", "toggleterm" },
      show_modified = false,
      kinds = Icons.kinds,
    },
  },

  {
    "folke/snacks.nvim",
    event = "VimEnter",
    opts = {
      dashboard = {
        preset = {
          header = Logos(),

          -- stylua: ignore
          keys = {
            { icon = " ",key = "r", desc = "Recent Files", action = ":lua Utils.pick('oldfiles')()", icon_hl = "DashboardRecent", key_hl = "DashboardRecent" },
            { icon = " ", key = "s", desc = "Last Session", action = ":lua require('persistence').load({last = true})", icon_hl = "DashboardSession", key_hl = "DashboardSession" },
            { icon = " ", key = "i", desc = "Configuration", action = ":edit $MYVIMRC", icon_hl = "DashboardConfiguration", key_hl = "DashboardConfiguration" },
            { icon = "󰤄 ", key = "l", desc = "Lazy", action = ":Lazy", icon_hl = "DashboardLazy", key_hl = "DashboardLazy" },
            { icon = " ", key = "m", desc = "Mason", action = ":Mason", icon_hl = "DashboardServer", key_hl = "DashboardServer" },
            { icon = " ", key = "q", desc = "Quit Neovim", action = ":qa", icon_hl = "DashboardQuit", key_hl = "DashboardQuit" },
          },
        },
      },
    },
  },

  {
    "petertriho/nvim-scrollbar",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      set_highlights = false,
      excluded_filetypes = {
        "prompt",
        "TelescopePrompt",
        "noice",
        "neo-tree",
        "dashboard",
        "alpha",
        "lazy",
        "mason",
        "DressingInput",
        "",
      },
      handlers = {
        gitsigns = true,
      },
    },
  },

  {
    "anuvyklack/windows.nvim",
    event = "WinNew",
    dependencies = {
      { "anuvyklack/middleclass" },
      { "anuvyklack/animation.nvim", enabled = true },
    },
    opts = {
      animation = { enable = true, duration = 150, fps = 60 },
      autowidth = { enable = true },
    },
    keys = { { "<leader>z", "<cmd>WindowsMaximize<CR>", desc = "Zoom window" } },
    init = function()
      vim.o.winwidth = 30
      vim.o.winminwidth = 30
      vim.o.equalalways = true
    end,
  },

  -- better vim.ui
  {
    "stevearc/dressing.nvim",
    event = { "BufReadPost", "BufNewFile" },
    opts = function()
      local monokai_opts = Utils.plugin.opts("monokai-pro.nvim")
      local border_style = vim.tbl_contains(monokai_opts.background_clear or {}, "float_win") and "rounded" or "thick"
      return {
        input = {
          border = Utils.ui.borderchars(border_style, "tl-t-tr-r-br-b-bl-l"),
          win_options = { winblend = 0 },
        },
        select = {},
      }
    end,
    init = function()
      vim.ui.select = function(...)
        ---@diagnostic disable-next-line: different-requires
        require("lazy").load({ plugins = { "dressing.nvim" } })
        return vim.ui.select(...)
      end
      vim.ui.input = function(...)
        ---@diagnostic disable-next-line: different-requires
        require("lazy").load({ plugins = { "dressing.nvim" } })
        return vim.ui.input(...)
      end
    end,
  },

  {
    "lukas-reineke/indent-blankline.nvim",
    event = { "BufReadPost", "BufNewFile", "BufWritePre" },
    opts = function()
      local hooks = require("ibl.hooks")
      hooks.register(hooks.type.SCOPE_ACTIVE, function(bufnr)
        return vim.api.nvim_buf_line_count(bufnr) < 2000
      end)

      local highlight = {
        "RainbowDelimiterRed",
        "RainbowDelimiterYellow",
        "RainbowDelimiterBlue",
        "RainbowDelimiterOrange",
        "RainbowDelimiterGreen",
        "RainbowDelimiterViolet",
        "RainbowDelimiterCyan",
      }
      return {
        debounce = 200,
        indent = {
          char = "▏",
          tab_char = "▏",
          -- highlight = "IndentBlanklineChar",
          -- highlight = highlight,
        },
        scope = {
          injected_languages = true,
          highlight = highlight,
          enabled = true,
          show_start = true,
          show_end = false,
          char = "▏",
          -- include = {
          --   node_type = { ["*"] = { "*" } },
          -- },
          -- exclude = {
          --   node_type = { ["*"] = { "source_file", "program" }, python = { "module" }, lua = { "chunk" } },
          -- },
        },
        exclude = {
          filetypes = {
            "help",
            "startify",
            "dashboard",
            "packer",
            "neogitstatus",
            "NvimTree",
            "Trouble",
            "alpha",
            "neo-tree",
          },
          buftypes = {
            "terminal",
            "nofile",
          },
        },
      }
    end,
    main = "ibl",
  },

  {
    "folke/snacks.nvim",
    opts = {
      indent = { enabled = false },
      input = { enabled = true },
      notifier = { enabled = true, style= "compact" },
      scope = { enabled = true },
      scroll = { enabled = false },
      statuscolumn = { enabled = false }, -- we set this in options.lua
      toggle = { map = Utils.safe_keymap_set },
      words = { enabled = true },
      styles = {
        notification = {
          border = Utils.ui.borderchars("rounded", "tl-t-tr-r-br-b-bl-l"),
          title_pos = "left",
          wo = {
            -- winhighlight = "LineNr:SnacksNotifierInfo",
            winhighlight = "LineNr:SnacksNotifierIconInfo ",
            winblend = 0,
            wrap = false,
            conceallevel = 0,
            colorcolumn = "",
          },
        },
      },
    },
    -- stylua: ignore
    keys = {
      { "<leader>n", function() Snacks.notifier.hide() end, desc = "Dismiss All Notifications" },
    },
  },

  {
    "echasnovski/mini.hipatterns",
    event = { "BufReadPost", "BufNewFile", "BufWritePre" },
    desc = "Highlight colors in your code. Also includes Tailwind CSS support.",
    opts = function()
      local hi = require("mini.hipatterns")
      return {
        highlighters = {
          -- Highlight standalone 'FIXME', 'HACK', 'TODO', 'NOTE'
          fixme = { pattern = "%f[%w]()FIXME()%f[%W]", group = "MiniHipatternsFixme" },
          hack = { pattern = "%f[%w]()HACK()%f[%W]", group = "MiniHipatternsHack" },
          todo = { pattern = "%f[%w]()TODO()%f[%W]", group = "MiniHipatternsTodo" },
          note = { pattern = "%f[%w]()NOTE()%f[%W]", group = "MiniHipatternsNote" },
          wip = { pattern = "%f[%w]()WIP()%f[%W]", group = "MiniHipatternsWip" },
          -- Highlight hex color strings (`#rrggbb`) using that color
          hex_color = hi.gen_highlighter.hex_color({ priority = 2000 }),
        },
      }
    end,
  },

  -- noicer ui
  {
    "folke/noice.nvim",
    event = "VeryLazy",
    opts = {
      cmdline = {
        enabled = true,
        view = "cmdline",
        format = {
          cmdline = { icon = "  " },
          search_down = { icon = " 🔍 󰄼" },
          search_up = { icon = " 🔍 " },
          help = { icon = " 󰋖" },
          lua = { icon = "  " },
        },
      },
      lsp = {
        progress = {
          enabled = true,
          format = "lsp_progress",
          format_done = "lsp_progress_done",
          view = "mini",
        },
        hover = { enabled = false },
        signature = { enabled = false },
        -- override markdown rendering so that **cmp** and other plugins use **Treesitter**
        override = {
          ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
          ["vim.lsp.util.stylize_markdown"] = true,
          ["cmp.entry.get_documentation"] = true,
        },
      },
      presets = {
        lsp_doc_border = true, -- add a border to hover docs and signature help
      },
      routes = {
        {
          filter = {
            event = "msg_show",
            any = {
              { find = "%d+L, %d+B" },
              { find = "No active Snippet" },
              { find = "; after #%d+" },
              { find = "; before #%d+" },
              { find = "Hunk" },
            },
          },
          view = "mini",
        },
        {
          filter = {
            event = "notify",
            any = {
              { find = "No information available" },
            },
          },
        },
      },
    },
  },
}
