local config = require("beast.libs.toast.config")

---@class Beast.Toast.Record
---@field id integer
---@field message string
---@field level string        "INFO"|"WARN"|"ERROR"|"DEBUG"|"TRACE"
---@field title string
---@field icon string
---@field dim boolean
---@field time integer        vim.fn.localtime()
---@field timeout number|false

---@overload fun(id: integer, message: string|string[], level?: string|integer, opts?: Beast.Toast.Options): Beast.Toast.Record
local M = setmetatable({}, {
	__call = function(t, ...)
		return t:new(...)
	end,
})

M.__index = M

---@class Beast.Toast.Options
---@field title? string
---@field icon? string
---@field dim? boolean
---@field timeout? number|false

---@param id integer
---@param message string|string[]
---@param level? string|integer
---@param opts? Beast.Toast.Options
---@return Beast.Toast.Record
function M:new(id, message, level, opts)
	opts = opts or {}
	level = config.normalize_level(level or "INFO")

	return setmetatable({
		id = id,
		message = config.normalize_message(message),
		level = level,
		title = opts.title or config.title or "",
		icon = opts.icon or config.icons[level] or "",
		dim = opts.dim == true,
		time = vim.fn.localtime(),
		timeout = opts.timeout ~= nil and opts.timeout or config.timeout,
	}, self)
end

function M:dimensions()
	local msg_str = config.normalize_message(self.message)
	local title_str = self.title or ""
	local title_w = (title_str ~= "" and (1 + vim.fn.strdisplaywidth(title_str)) or 0)
	local icon_str = self.icon or ""
	local icon_w = (icon_str ~= "" and (1 + vim.fn.strdisplaywidth(icon_str)) or 0)
	local msg_w = vim.fn.strdisplaywidth(msg_str)
	local max_w = type(config.max_width) == "function" and config.max_width() or config.max_width
	local width = math.min(max_w, math.max(10, msg_w + title_w + icon_w))
	return width, 1
end

return M
