---@class Beast.Indent.Config
local defaults = {
	guide = {
		enabled = true,
		symbol = "▏",
		priority = 1,
	},
	scope = {
		enabled = true,
		symbol = "▏",
		priority = 200,
		debounce = 30, -- ms
		underline = true,
		treesitter = {
			enabled = true,
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
		},
	},
	exclude_filetypes = {
		"help",
		"beast-backdrop",
		"beast-confirm",
		"beast-explorer",
		"beast-explorer-sticky",
		"beast-finder-backdrop",
		"beast-finder-input",
		"beast-finder-list",
		"beast-finder-preview",
		"beast-key",
		"beast-key-actions",
		"beast-notify",
		"beast-packer",
		"beast-packer-actions",
		"beast-starter",
		"beast-toast",
	},
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
