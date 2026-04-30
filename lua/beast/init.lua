local M = {}

---@class Beast.Config
---@field key? Beast.Key.Config
---@field notify? Beast.Notify.Config
local defaults = {
	key = {},
	notify = {},
	toast = { disabled = false },
	packer = {
		{ import = "beast.plugins" },
	},
}

---@param opts? Beast.Config
function M.setup(opts)
	local cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

	require("beast.option")

	_G.Util = require("beast.util")
	_G.Key = require("beast.libs.key")
	_G.Buffer = require("beast.libs.buf")
	_G.Icon = require("beast.icon")

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
	---@type Beast.Packer.PluginSpec[]
	packer.setup(cfg.packer)
end

return M
