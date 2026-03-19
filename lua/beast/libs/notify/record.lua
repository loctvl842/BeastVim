local config = require("beast.libs.notify.config")

---@class Beast.Notify.Record
---@field id integer
---@field message string[]
---@field level string        "INFO"|"WARN"|"ERROR"|"DEBUG"|"TRACE"
---@field title string
---@field icon string
---@field time integer        vim.fn.localtime()
---@field timeout number|false
local M = setmetatable({}, {
	__call = function(t, ...)
		return t:new(...)
	end,
})

M.__index = M

---@class Beast.Notify.Options
---@field title? string
---@field icon? string
---@field timeout? number|false

---@param id integer
---@param message string|string[]
---@param level? string|integer
---@param opts? Beast.Notify.Options
---@return Beast.Notify.Record
function M:new(id, message, level, opts)
	opts = opts or {}
	level = config.normalize_level(level or "INFO")

	return setmetatable({
		id = id,
		message = config.normalize_message(message),
		level = level,
		title = opts.title or "",
		icon = opts.icon or config.icons[level] or "",
		time = vim.fn.localtime(),
		timeout = opts.timeout ~= nil and opts.timeout or config.timeout,
	}, self)
end

---@return integer width, integer height
function M:dimensions()
	local height = math.min(#self.message, config.max_height) + 1
	return config.width, height
end

return M
