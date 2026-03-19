---@class Beast.Notify.Config
local defaults = {
	width = 50,
	timeout = 3000,
	stagger = 100,
	max_height = 10,
	level = vim.log.levels.INFO,
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

---@type Beast.Notify.Config
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

---@param message string|string[]
---@return string[]
function methods.normalize_message(message)
	if type(message) == "string" then
		return vim.split(message, "\n", { plain = true })
	end
	return message
end

---@param opts? Beast.Notify.Config
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
				"beast.notify.config is read-only; cannot assign '%s' directly. Use setup() instead.",
				tostring(key)
			),
			2
		)
	end,
})

return M
