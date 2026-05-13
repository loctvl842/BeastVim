---@class Beast.Indent.Config
local defaults = {
	char = "▏",
	priority = 1,
	---@type string|string[]
	hl = "BeastIndentGuide",
	---@param buf number
	---@param win number
	---@return boolean
	filter = function(buf, win)
		return vim.bo[buf].buftype == ""
	end,
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
