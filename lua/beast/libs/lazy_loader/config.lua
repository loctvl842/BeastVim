---@class Beast.LazyLoader.Config
local defaults = {
	ui = {
		icons = {
			loaded = " ", -- check / success
			pending = " ", -- hollow circle
			event = " ", -- lightning / event

			keys = " ", -- keyboard
			cmd = " ", -- terminal / command
			module = "󰆧 ", -- package / module
			filetype = "", -- filetype / document
			lazy = "󰒲 ", -- sleep / idle
			eager = " ", -- eager / immediate
			dependencies = " ", -- dependency icon

			path = "󰉓 ", -- folder/path icon

			-- Operation status icons
			success = "✓",
			error = "✗",
		},
	},
}

---@type Beast.LazyLoader.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param opts? Beast.LazyLoader.Config
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
		error(
			string.format(
				"beast.lazy_loader.config is read-only; cannot assign '%s' directly. Use setup() instead.",
				tostring(key)
			),
			2
		)
	end,
})

return M
