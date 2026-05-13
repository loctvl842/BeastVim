---@class Beast.Toast.Config
local defaults = {
	timeout = 2200,
	stagger = 70,
	anim_ms = 180,
	gap = 0,
	margin_bottom = 0,
	level = vim.log.levels.INFO,
	title = "",
	max_width = function()
		return math.floor(vim.o.columns * 0.6)
	end,
	icons = {
		ERROR = "",
		WARN = "",
		HINT = "",
		INFO = "",
		DEBUG = "",
		TRACE = "",
	},
	hl = {
		ERROR = { title = "DiagnosticError", body = "Normal" },
		WARN = { title = "DiagnosticWarn", body = "Normal" },
		INFO = { title = "DiagnosticInfo", body = "Normal" },
		DEBUG = { title = "DiagnosticHint", body = "Normal" },
		TRACE = { title = "Comment", body = "Normal" },
	},
}

---@type Beast.Toast.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

local level_names = {}
for k, v in pairs(vim.log.levels) do
	level_names[v] = k
end

function methods.normalize_level(level)
	if type(level) == "number" then
		level = level_names[level] or "INFO"
		---@cast level string
	end
	return vim.fn.toupper(level)
end

---Collapse a multi-line message into a single line.
---@param message string|string[]
---@return string
function methods.normalize_message(message)
	if type(message) == "table" then
		message = table.concat(message, " ")
	end
	-- Replace embedded newlines with a single space so the toast stays single-line.
	return (message:gsub("[\r\n]+", " "))
end

---@param opts? Beast.Toast.Config
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
		error(string.format("beast.toast.config is read-only; cannot assign '%s' directly. Use setup() instead.", tostring(key)), 2)
	end,
})

return M
