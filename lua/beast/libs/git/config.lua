---@class Beast.Git.PreviewConfig
---@field context_size? integer Lines of unchanged context shown around the hunk in the preview float (default 3)
---@field width? "full"|"fit" Float sizing: "full" (full editor width) or "fit" (snug around content). Default "full".
---@field max_height? number Max float height. Integer = absolute rows, float in (0,1] = fraction of `vim.o.lines`. Default 0.4.
---@field adjacent_gap? integer Max unchanged lines between two hunks for them to be auto-merged in the preview. 0 = only touching hunks merge. Default 0.

---@class Beast.Git.Config
local defaults = {
	---@type integer Debounce window (ms) for TextChanged / TextChangedI re-diffs.
	debounce_ms = 200,

	---@type Beast.Git.PreviewConfig
	preview = {
		context_size = 3,
		width = "full",
		max_height = 0.4,
		adjacent_gap = 0,
	},

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
