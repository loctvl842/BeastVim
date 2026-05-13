local M = {}

---@class Beast.Config
---@field key? Beast.Key.Config
---@field notify? Beast.Notify.Config
---@field toast? table
---@field explorer? Beast.Explorer.Config
---@field packer? Beast.Packer.Config
---@field treesitter? Beast.Treesitter.Config
local defaults = {
	key = {},
	notify = {},
	toast = { disabled = false },
	explorer = {
		icon = {
			dir_open = "󰝰", -- nf-md-folder_open
			dir_closed = "󰉋", -- nf-md-folder
		},
		mappings = {
			["l"] = "open",
		},
	},
	packer = {
		colorscheme = { name = "monokai-pro", plugin = "monokai-pro.nvim" },
		-- colorscheme = { name = "tokyonight", plugin = "tokyonight.nvim" },
		spec = {
			{ import = "beast.plugins" },
		},
		ui = {},
	},
	treesitter = {
		ensure_installed = { "python", "lua" },
	},
}

---@param opts? Beast.Config
function M.setup(opts)
	local cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

	require("beast.option")

	_G.Util = require("beast.util")
	_G.Palette = require("beast.palette")
	_G.Key = require("beast.libs.key")
	_G.Buffer = require("beast.libs.buf")
	_G.Icon = require("beast.icon")

	-- Refresh palette + reload all Beast highlights on colorscheme change
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("BeastPalette", { clear = true }),
		callback = function()
			vim.schedule(function()
				Palette.refresh()
				M.reload_highlights()
			end)
		end,
	})

	Key.setup(cfg.key)

	Key.safe_set("n", "<leader>d", Buffer.delete, { desc = "Close current buffer", group = "Buffer" })

	-- Notification
	local notify = require("beast.libs.notify")
	notify.setup(cfg.notify)
	local toast = require("beast.libs.toast")
	toast.setup(cfg.toast)
	_G.Toast = toast

	Key.safe_set("n", "<leader>n", function()
		notify.dismiss()
		toast.dismiss()
	end, { desc = "Dismiss all notifications", group = "Notify" })

	require("beast.libs.confirm").setup()

	local packer = require("beast.libs.packer")

	-- stylua: ignore
	_G.gh = function(x) return "https://github.com/" .. x end
	---@type Beast.Packer.Config
	packer.setup(cfg.packer)

	-- Statusline (declarative components, native %! evaluation)
	local stl = require("beast.libs.statusline")
	local cpn = require("beast.libs.statusline.components")
	stl.setup({
		left = { cpn.git_branch, cpn.diagnostics },
		right = { cpn.git_commit, cpn.position, cpn.filetype, cpn.shiftwidth, cpn.encoding, cpn.mode },
	})

	-- Tabline (lazy — deferred past first screen update)
	packer.lazy("beast.libs.tabline", {
		event = "VimEnter",
		defer = true,
		highlights = "beast.libs.tabline.highlights",
		setup = function(tabline)
			tabline.setup({
				max_name_width = 30,
				min_cell_width = 18,
				sidebar_filetypes = { ["beast-explorer"] = "EXPLORER" },
				show_close_button = true,
				show_modified = true,
				show_diagnostics = true,
			})
		end,
	})

	vim.g.loaded_netrw = 1
	vim.g.loaded_netrwPlugin = 1
	-- Explorer (lazy — deferred to first <leader>e press or VimEnter with no file)
	packer.lazy("beast.libs.explorer", {
		keys = { {
			"<leader>e",
			function()
				require("beast.libs.explorer").toggle()
			end,
			desc = "Toggle explorer panel",
			group = "Explorer",
		} },
		event = "VimEnter",
		defer = true,
		highlights = "beast.libs.explorer.highlights",
		setup = function(explorer)
			explorer.setup(cfg.explorer)
			-- Detect directory buffers from startup (e.g. `nvim ~/Downloads`),
			-- capture the path and wipe the buffer before opening the explorer.
			for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				local name = vim.api.nvim_buf_get_name(buf)
				if name ~= "" and vim.fn.isdirectory(name) == 1 then
					local dir = vim.fn.fnamemodify(name, ":p"):gsub("/$", "")
					pcall(vim.api.nvim_buf_delete, buf, { force = true })
					explorer.open(dir)
					return
				end
			end
			-- No directory buffer found — auto-open when nvim started with no file
			if vim.fn.argc() == 0 and vim.api.nvim_buf_get_name(0) == "" then
				explorer.open()
			end
		end,
	})

	-- Treesitter (lazy — enable builtin highlighting + fold on FileType)
	packer.lazy("beast.libs.treesitter", {
		event = "FileType",
		defer = true,
		setup = function(ts)
			ts.setup(cfg.treesitter)
			ts.enable()
		end,
	})

	-- Initial palette extraction (colorscheme should be loaded by packer)
	Palette.refresh()
	M.reload_highlights()
end

--- Registry of highlight modules to reload on ColorScheme change.
--- Lazy-loaded libs register their highlights dynamically via packer.lazy().
---@type string[]
M.highlight_modules = {
	"beast.libs.confirm.highlights",
	"beast.libs.key.highlights",
	"beast.libs.packer.highlights",
	"beast.libs.notify.highlights",
	"beast.libs.statusline.highlights",
}

--- Reload all Beast lib highlights.
--- Skips modules whose parent lib hasn't been loaded yet.
function M.reload_highlights()
	for _, mod_name in ipairs(M.highlight_modules) do
		local parent = mod_name:gsub("%.highlights$", "")
		-- stylua: ignore
		if not package.loaded[parent] then goto continue end
		package.loaded[mod_name] = nil
		pcall(require, mod_name)
		::continue::
	end
end

return M
