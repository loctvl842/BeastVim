local ui = require("beast.libs.packer.ui")
local state = require("beast.libs.packer.state")

local M = {}

-- Mock plugin specs
local function populate_mock_data()
	-- Add some mock plugins to state
	state.lazy_plugins = {
		{
			name = "telescope.nvim",
			src = "https://github.com/nvim-telescope/telescope.nvim",
			lazy = { cmd = "Telescope" },
		},
		{
			name = "neo-tree.nvim",
			src = "https://github.com/nvim-neo-tree/neo-tree.nvim",
			lazy = { cmd = "Neotree" },
		},
		{
			name = "treesitter",
			src = "https://github.com/nvim-treesitter/nvim-treesitter",
			lazy = { event = "BufReadPre" },
		},
		{
			name = "lsp-config",
			src = "https://github.com/neovim/nvim-lspconfig",
			lazy = { event = "BufReadPre" },
		},
		{
			name = "nvim-cmp",
			src = "https://github.com/hrsh7th/nvim-cmp",
			lazy = { event = "InsertEnter" },
		},
		{
			name = "luasnip",
			src = "https://github.com/L3MON4D3/LuaSnip",
			lazy = { event = "InsertEnter" },
		},
		{
			name = "vim-fugitive",
			src = "https://github.com/tpope/vim-fugitive",
			lazy = { cmd = { "Git", "Gstatus" } },
		},
		{
			name = "nvim-notify",
			src = "https://github.com/rcarriga/nvim-notify",
			lazy = false, -- eager
		},
	}

	-- Mark some plugins as loaded with mock profiles
	state.loaded_plugins["nvim-notify"] = true
	state.load_profiles["nvim-notify"] = {
		packadd_ms = 2.5,
		config_ms = 1.2,
		total_ms = 3.7,
		reason = { type = "eager" },
	}

	state.loaded_plugins["lsp-config"] = true
	state.load_profiles["lsp-config"] = {
		packadd_ms = 15.3,
		config_ms = 8.7,
		total_ms = 24.0,
		reason = { type = "event", detail = "BufReadPre" },
	}

	state.loaded_plugins["treesitter"] = true
	state.load_profiles["treesitter"] = {
		packadd_ms = 12.1,
		config_ms = 5.3,
		total_ms = 17.4,
		reason = { type = "event", detail = "BufReadPre" },
	}

	state.loaded_plugins["nvim-cmp"] = true
	state.load_profiles["nvim-cmp"] = {
		packadd_ms = 8.9,
		config_ms = 3.1,
		total_ms = 12.0,
		reason = { type = "event", detail = "InsertEnter" },
	}
end

function M.show_main()
	populate_mock_data()
	ui.open()
end

function M.show_profile()
	populate_mock_data()
	ui.open()
	local state_data = require("beast.libs.packer.ui")
end

function M.show_help()
	populate_mock_data()
	ui.open()
end

function M.test_render()
	populate_mock_data()
	ui.open()
	print("UI opened with mock data. Press 'q' to close.")
end

function M.test_sort_toggle()
	populate_mock_data()
	local view = ui.create()
	view.view_mode = "main"
	view.sort_mode = "name"

	print("Rendering with sort_mode = name...")
	ui.render(view)

	view.sort_mode = "time"
	print("Rendering with sort_mode = time...")
	ui.render(view)

	ui.close(view)
	print("Sort toggle test passed!")
end

return M
