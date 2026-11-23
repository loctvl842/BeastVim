-- Symbol kind tables: LSP `SymbolKind` number -> `Icon.kinds` key, and key -> color family.

local M = {}

---@type string[]  Indexed by LSP SymbolKind (1..26)
M.by_number = {
	"File",
	"Module",
	"Namespace",
	"Package",
	"Class",
	"Method",
	"Property",
	"Field",
	"Constructor",
	"Enum",
	"Interface",
	"Function",
	"Variable",
	"Constant",
	"String",
	"Number",
	"Boolean",
	"Array",
	"Object",
	"Key",
	"Null",
	"EnumMember",
	"Struct",
	"Event",
	"Operator",
	"TypeParameter",
}

---@type table<string, "Callable"|"Type"|"Module">
local families = {
	Function = "Callable",
	Method = "Callable",
	Constructor = "Callable",
	Operator = "Callable",
	Event = "Callable",
	Class = "Type",
	Struct = "Type",
	Interface = "Type",
	Enum = "Type",
	TypeParameter = "Type",
	File = "Module",
	Module = "Module",
	Namespace = "Module",
	Package = "Module",
}

---Resolve an LSP SymbolKind number to an `Icon.kinds` key. Unknown numbers fall back to Variable.
---@param number integer
---@return string
function M.name(number)
	return M.by_number[number] or "Variable"
end

---Highlight family suffix for a kind key (BeastBcSym<Family>).
---@param key string
---@return "Callable"|"Type"|"Module"|"Value"
function M.family(key)
	return families[key] or "Value"
end

return M
