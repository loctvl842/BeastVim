---@class Beast.Indent.Config
local defaults = {
	draw = { delay = 1, priority = 2 },
	guide = {
		enabled = true,
		symbol = "▏",
		priority = 1,
	},
	exclude_filetypes = {
		"help",
		"beast-backdrop",
		"beast-confirm",
		"beast-explorer",
		"beast-explorer-sticky",
		"beast-finder-backdrop",
		"beast-finder-input",
		"beast-finder-list",
		"beast-finder-preview",
		"beast-key",
		"beast-key-actions",
		"beast-notify",
		"beast-packer",
		"beast-packer-actions",
		"beast-toast",
	},
	scope = "▏",
}

---@type Beast.Indent.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param opts? Beast.Indent.Config
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
		error(string.format("beast.indent.config is read-only; cannot assign '%s' directly. Use setup() instead.", tostring(key)), 2)
	end,
})

return M
