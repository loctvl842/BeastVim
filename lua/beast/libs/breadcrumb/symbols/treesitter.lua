-- Treesitter symbol source: fallback for buffers without a symbol-providing language server.
--
-- Walks the ancestors of the node under the cursor and keeps those listed in the
-- buffer language's table. Each entry gives the symbol kind (an `Icon.kinds` key) and
-- a function returning the symbol name (nil/empty skips the node). Node and field names
-- are grammar specific, so each language is verified by tests/test-breadcrumb-symbols.lua.

local M = {}

---@alias Beast.Breadcrumb.TsNamer fun(node: TSNode, bufnr: integer): string?
---@alias Beast.Breadcrumb.TsSpec { kind: string, name: Beast.Breadcrumb.TsNamer }

---@param node TSNode?
---@param bufnr integer
---@return string?
local function text(node, bufnr)
	return node and vim.treesitter.get_node_text(node, bufnr) or nil
end

---Name is the text of a named field.
---@param field string
---@return Beast.Breadcrumb.TsNamer
local function field_text(field)
	return function(node, bufnr)
		return text(node:field(field)[1], bufnr)
	end
end

---Like `field_text`, but only for definitions: forward declarations and type references have no body.
---@param field string
---@return Beast.Breadcrumb.TsNamer
local function field_text_with_body(field)
	local name = field_text(field)
	return function(node, bufnr)
		return node:field("body")[1] and name(node, bufnr) or nil
	end
end

---Name an anonymous function after what it is assigned to (`x = function`, `key: () =>`).
---@param node TSNode  The function node
---@param bufnr integer
---@return string?
local function assigned_name(node, bufnr)
	local parent = node:parent()
	if not parent then
		return
	end
	local ptype = parent:type()
	if ptype == "variable_declarator" or ptype == "public_field_definition" then
		return text(parent:field("name")[1], bufnr)
	elseif ptype == "pair" then
		return text(parent:field("key")[1], bufnr)
	elseif ptype == "field" then
		return text(parent:field("name")[1], bufnr)
	elseif ptype == "expression_list" then
		-- lua: `a.b = function() end`; the value list sits under the assignment
		local assignment = parent:parent()
		local targets = assignment and assignment:type() == "assignment_statement" and assignment:named_child(0)
		return text(targets and targets:named_child(0), bufnr)
	end
end

---C/C++ names live at the bottom of a chain of `declarator` fields (pointers, references, ...).
---@param node TSNode
---@param bufnr integer
---@return string?
local function declarator_name(node, bufnr)
	local decl = node:field("declarator")[1]
	while decl and decl:field("declarator")[1] do
		decl = decl:field("declarator")[1]
	end
	return text(decl, bufnr)
end

---Markdown: a `section` is named after its heading.
---@param node TSNode
---@param bufnr integer
---@return string?
local function heading_name(node, bufnr)
	local heading = node:named_child(0)
	if not heading or not heading:type():find("heading", 1, true) then
		return
	end
	local name = text(heading:field("heading_content")[1], bufnr)
	return name and vim.trim(name)
end

---@type table<string, Beast.Breadcrumb.TsSpec>
local ecma = {
	class_declaration = { kind = "Class", name = field_text("name") },
	abstract_class_declaration = { kind = "Class", name = field_text("name") },
	interface_declaration = { kind = "Interface", name = field_text("name") },
	enum_declaration = { kind = "Enum", name = field_text("name") },
	internal_module = { kind = "Namespace", name = field_text("name") },
	method_definition = { kind = "Method", name = field_text("name") },
	function_declaration = { kind = "Function", name = field_text("name") },
	generator_function_declaration = { kind = "Function", name = field_text("name") },
	arrow_function = { kind = "Function", name = assigned_name },
	function_expression = { kind = "Function", name = assigned_name },
}

---@type table<string, Beast.Breadcrumb.TsSpec>
local c = {
	function_definition = { kind = "Function", name = declarator_name },
	struct_specifier = { kind = "Struct", name = field_text_with_body("name") },
	enum_specifier = { kind = "Enum", name = field_text_with_body("name") },
}

---@type table<string, table<string, Beast.Breadcrumb.TsSpec>>
local SPECS = {
	lua = {
		function_declaration = { kind = "Function", name = field_text("name") },
		function_definition = { kind = "Function", name = assigned_name },
	},
	python = {
		class_definition = { kind = "Class", name = field_text("name") },
		function_definition = { kind = "Function", name = field_text("name") },
	},
	javascript = ecma,
	typescript = ecma,
	tsx = ecma,
	c = c,
	cpp = vim.tbl_extend("force", c, {
		namespace_definition = { kind = "Namespace", name = field_text("name") },
		class_specifier = { kind = "Class", name = field_text_with_body("name") },
	}),
	markdown = {
		section = { kind = "Module", name = heading_name },
	},
}

---Symbols containing (row, col), outermost first. `nil` when this source has nothing for the
---buffer (no spec for its language, or no parser); `{}` when the cursor is outside every symbol.
---@param bufnr integer
---@param row integer  0-indexed
---@param col integer  0-indexed byte column
---@return Beast.Breadcrumb.Symbol[]?
function M.trail(bufnr, row, col)
	local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
	local specs = lang and SPECS[lang]
	if not specs then
		return nil
	end

	local parser = vim.treesitter.get_parser(bufnr, lang, { error = false })
	if not parser then
		return nil
	end
	parser:parse()

	local trail = {}
	local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { row, col } })
	while node do
		local spec = specs[node:type()]
		local name = spec and spec.name(node, bufnr)
		if name and name ~= "" then
			table.insert(trail, 1, { name = name, kind = spec.kind })
		end
		node = node:parent()
	end
	return trail
end

return M
