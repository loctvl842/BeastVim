---@class Beast.Statuscolumn.GitConfig
---@field enabled? boolean Silently no-op when false; gitsigns/mini.diff still auto-detected when true

---@class Beast.Statuscolumn.FoldIcons
---@field open? string Glyph shown on the first line of an open fold (only when fold.open=true)
---@field close? string Glyph shown on the first line of a closed fold

---@class Beast.Statuscolumn.FoldConfig
---@field open? boolean Render the open-fold glyph on the first line of an open fold
---@field icons? Beast.Statuscolumn.FoldIcons Override `&fillchars` glyphs

--- Each entry in `segments` is one slot (one rendered cell). A slot is an
--- ordered list of producer names; the first producer with output for the
--- current line wins. Producers: "number" | "diagnostic" | "git" | "fold".
---@alias Beast.Statuscolumn.Slot string[]

---@class Beast.Statuscolumn.Config
local defaults = {
	---@type Beast.Statuscolumn.GitConfig
	git = { enabled = true },

	---@type Beast.Statuscolumn.FoldConfig
	fold = { open = false, icons = { open = "", close = "" } },

	---@type Beast.Statuscolumn.Slot[]
	segments = {
		{ "diagnostic" },
		{ "number" },
		{ "git" },
		{ "fold" },
	},

	---@type string[]
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

	---@type string[]
	bt_ignore = {
		"nofile",
		"prompt",
		"quickfix",
		"terminal",
	},
}

---@type Beast.Statuscolumn.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param opts? Beast.Statuscolumn.Config
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
		error(string.format("beast.libs.statuscolumn.config is read-only; cannot assign '%s' directly. Use setup() instead.", tostring(key)), 2)
	end,
})

return M
