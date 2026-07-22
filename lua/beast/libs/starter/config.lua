---@class Beast.Starter.Config
local defaults = {
	enabled = true,
	---@type { verb: string, key: string, desc: string, action?: fun() }[]
	-- Keymap rows shown under the native intro. When empty the BeastVim
	-- section is skipped entirely and the layout matches the stock intro.
	-- Rows with an `action` are mapped on the starter buffer and unmap
	-- themselves after firing once; rows without one are display-only.
	keys = {},
}

---@type Beast.Starter.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param opts? Beast.Starter.Config
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
		error(string.format("beast.starter.config is read-only; cannot assign '%s' directly. Use setup() instead.", tostring(key)), 2)
	end,
})

return M
