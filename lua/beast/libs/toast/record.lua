local config = require("beast.libs.toast.config")

---@class Beast.Toast.Fragment
---@field text string
---@field hl? string         hl_group; defaults to "BeastToastBody"
-- Same shape as Beast.Statusline.Fragment (see ADR-012).

---@class Beast.Toast.Record
---@field id integer
---@field message string
---@field segments? Beast.Toast.Fragment[]   when set, replaces the single Body extmark with per-segment highlights
---@field level string        "INFO"|"WARN"|"ERROR"|"DEBUG"|"TRACE"
---@field title string
---@field icon string
---@field dim boolean
---@field time integer        vim.fn.localtime()
---@field timeout number|false
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
---@field segments? Beast.Toast.Fragment[]

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
		segments = opts.segments,
		level = level,
		title = opts.title or config.title or "",
		icon = opts.icon or config.icons[level] or "",
		dim = opts.dim == true,
		time = vim.fn.localtime(),
		timeout = opts.timeout ~= nil and opts.timeout or config.timeout,
	}, self)
end

function M:dimensions()
	local title_str = self.title or ""
	local title_w = (title_str ~= "" and (1 + vim.fn.strdisplaywidth(title_str)) or 0)
	local icon_str = self.icon or ""
	local icon_w = (icon_str ~= "" and (1 + vim.fn.strdisplaywidth(icon_str)) or 0)

	local msg_w
	if self.segments then
		msg_w = 0
		for _, seg in ipairs(self.segments) do
			msg_w = msg_w + vim.fn.strdisplaywidth(seg.text or "")
		end
	else
		msg_w = vim.fn.strdisplaywidth(config.normalize_message(self.message))
	end

	local max_w = type(config.max_width) == "function" and config.max_width() or config.max_width
	local width = math.min(max_w, math.max(10, msg_w + title_w + icon_w))
	return width, 1
end

return M
