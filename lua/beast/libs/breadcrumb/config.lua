---@class Beast.Breadcrumb.Config
local defaults = {
	-- Separator between path segments (chevron right)
	separator = "  ",

	-- Filetypes that should not show the winbar
	---@type table<string, true>
	ignored_filetypes = {
		["beast-backdrop"] = true,
		["beast-confirm"] = true,
		["beast-explorer"] = true,
		["beast-key"] = true,
		["beast-key-actions"] = true,
		["beast-notify"] = true,
		["beast-packer"] = true,
		["beast-packer-actions"] = true,
		["beast-toast"] = true,
	},

	-- Buftypes that should not show the winbar
	---@type table<string, true>
	ignored_buftypes = {
		nofile = true,
		prompt = true,
		help = true,
		quickfix = true,
		terminal = true,
	},

	-- Modified indicator
	modified_icon = "",
}

---@type Beast.Breadcrumb.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param opts? Beast.Breadcrumb.Config
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
		error(string.format("beast.libs.breadcrumb.config is read-only; cannot assign '%s' directly. Use setup() instead.", tostring(key)), 2)
	end,
})

return M
