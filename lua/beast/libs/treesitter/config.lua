---@class Beast.Treesitter.Config
local defaults = {
	---@type string[]
	ensure_installed = {},
	highlight = {
		enable = true,
	},
	fold = {
		enable = false,
	},
	-- Node types considered "scope" for scope detection (Phase 2).
	-- Applies across all languages; per-language overrides may be added later.
	---@type string[]
	scope_types = {
		"function",
		"function_definition",
		"function_declaration",
		"method",
		"method_definition",
		"method_declaration",
		"if_statement",
		"for_statement",
		"for_in_statement",
		"while_statement",
		"repeat_statement",
		"do_statement",
		"class_definition",
		"class_declaration",
		"module",
	},
}

---@type Beast.Treesitter.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param opts? Beast.Treesitter.Config
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
		error(string.format("beast.treesitter.config is read-only; cannot assign '%s' directly. Use setup() instead.", tostring(key)), 2)
	end,
})

return M
