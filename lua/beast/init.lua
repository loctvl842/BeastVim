local M = {}

---@class Beast.Config
---@field key? Beast.Key.Config
---@field notify? Beast.Notify.Config
---@field toast? table
---@field packer? Beast.Packer.Config
local defaults = {
	key = {},
	notify = {},
	toast = { disabled = false },
	packer = {
		colorscheme = { name = "monokai-pro", plugin = "monokai-pro.nvim" },
		spec = {
			{ import = "beast.plugins" },
		},
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

	local explorer = require("beast.libs.explorer")
	explorer.setup({
		style = "classic",
		width = 40, -- panel columns
		side = "left", -- "left" | "right"
		show_hidden = false, -- toggle with your own keymap later
		icons = true, -- requires nvim-web-devicons
		git = true, -- async git status
		icon = {
			dir_open = "󰝰", -- nf-md-folder_open
			dir_closed = "󰉋", -- nf-md-folder
		},
		mappings = {
			["l"] = "open",
		},
	})
	Key.safe_set("n", "<leader>e", explorer.toggle, { desc = "Toggle explorer panel", group = "Explorer" })

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

	-- Initial palette extraction (colorscheme should be loaded by packer)
	Palette.refresh()
	M.reload_highlights()
end

--- Registry of highlight modules to reload on ColorScheme change.
---@type string[]
M.highlight_modules = {
	"beast.libs.confirm.highlights",
	"beast.libs.explorer.highlights",
	"beast.libs.key.highlights",
	"beast.libs.packer.highlights",
	"beast.libs.notify.highlights",
	"beast.libs.statusline.highlights",
}

--- Reload all Beast lib highlights.
function M.reload_highlights()
	for _, mod_name in ipairs(M.highlight_modules) do
		package.loaded[mod_name] = nil
		pcall(require, mod_name)
	end
end

return M
