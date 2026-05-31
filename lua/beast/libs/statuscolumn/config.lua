---@class Beast.Statuscolumn.GitIcons
---@field add? string
---@field change? string
---@field delete? string
---@field topdelete? string
---@field changedelete? string

---@class Beast.Statuscolumn.GitConfig
---@field enabled? boolean Silently no-op when false; gitsigns/mini.diff still auto-detected when true
---@field icons? Beast.Statuscolumn.GitIcons Glyphs rendered for `beast.libs.git` markers (foreign plugins keep their own glyphs)

---@class Beast.Statuscolumn.FoldIcons
---@field open? string Glyph shown on the first line of an open fold (only when fold.open=true)
---@field close? string Glyph shown on the first line of a closed fold

---@class Beast.Statuscolumn.FoldConfig
---@field open? boolean Render the open-fold glyph on the first line of an open fold
---@field icons? Beast.Statuscolumn.FoldIcons Override `&fillchars` glyphs

--- Each entry in `segments` is one slot (one rendered cell). A slot is an
--- ordered list of producer names; the first producer with output for the
--- current line wins. Producers: "number" | "diagnostic" | "git" | "fold".
---
--- Two forms:
---   shorthand: `{ "git", "fold" }` — 1-cell sign slot, priority order
---   full:      `{ producers = { "git", "fold" }, width = 2 }`
--- `width` (full form only) reserves N cells; the matched glyph is padded
--- on the right with spaces to that width. Only meaningful for sign-style
--- slots; ignored for slots that don't include diagnostic/git/fold.
---@alias Beast.Statuscolumn.Slot string[] | { producers: string[], width?: integer }

---@class Beast.Statuscolumn.Config
local defaults = {
	---@type Beast.Statuscolumn.GitConfig
	git = {
		enabled = true,
		-- Default glyphs (1-cell). Source of truth for the gutter; `beast.libs.git`
		-- writes only a typed marker (sign_name="beast_git_<type>") and this lib
		-- decides what to render.
		icons = {
			add = "│",
			change = "┊",
			delete = "",
			topdelete = "",
			changedelete = "│",
		},
	},

	---@type Beast.Statuscolumn.FoldConfig
	fold = { open = true, icons = { open = "", close = "" } },

	---@type Beast.Statuscolumn.Slot[]
	segments = {
		{ "diagnostic" },
		{ "number" },
		{ "git" },
		{ producers = { "fold" }, width = 2 },
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
