---@class Beast.Git.Icons
---@field add? string
---@field change? string
---@field delete? string
---@field topdelete? string
---@field changedelete? string

---@class Beast.Git.Config
local defaults = {
	---@type integer Debounce window (ms) for TextChanged / TextChangedI re-diffs.
	debounce_ms = 200,

	---@type boolean Register default `]c` / `[c` / `<leader>gp` keymaps on attach (Phase 2/3 features).
	keymaps = true,

	---@type Beast.Git.Icons? Override the icons sourced from `beast.icon.gitsigns`.
	icons = nil,

	---@type string[] Filetypes that never attach.
	ft_ignore = {
		"help",
		"alpha",
		"dashboard",
		"lazy",
		"mason",
		"netrw",
		"NvimTree",
		"beast-explorer",
		"TelescopePrompt",
		"toggleterm",
		"trouble",
		"qf",
		"man",
		"checkhealth",
	},

	---@type string[] Buftypes that never attach.
	bt_ignore = {
		"nofile",
		"prompt",
		"quickfix",
		"terminal",
		"help",
	},
}

---@type Beast.Git.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param opts? Beast.Git.Config
function methods.setup(opts)
	cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

local M = setmetatable({}, {
	__index = function(_, key)
		if methods[key] ~= nil then
			return methods[key]
		end
		return cfg[key]
	end,

	__newindex = function(_, key, _)
		error(string.format("beast.libs.git.config is read-only; cannot assign '%s' directly. Use setup() instead.", tostring(key)), 2)
	end,
})

return M
