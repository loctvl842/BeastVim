--- Each entry in `segments` is one slot (one rendered cell). A slot is an
--- ordered list of producer names; the first producer with output for the
--- current line wins. Producers: "number" | "diagnostic" | "git" | "fold".
---@alias Beast.Statuscolumn.Slot string[]

---@class Beast.Statuscolumn.Config
local defaults = {
	---@type Beast.Statuscolumn.Slot[]
	segments = {
		{ "number" },
	},

	---@type string[] Filetypes that disable the lib for the buffer (Phase 3 will populate)
	ft_ignore = {},

	---@type string[] Buftypes that disable the lib for the buffer (Phase 3 will populate)
	bt_ignore = {},
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
