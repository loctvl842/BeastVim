---@class Beast.Session.Config
local defaults = {
	-- Directory where session files are saved
	dir = vim.fn.stdpath("state") .. "/sessions/",
}

---@type Beast.Session.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param opts? Beast.Session.Config
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
		error(string.format("beast.libs.session.config is read-only; cannot assign '%s' directly. Use setup() instead.", tostring(key)), 2)
	end,
})

return M
