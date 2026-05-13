local config = require("beast.libs.treesitter.config")

local M = {}

-- Lookup set built lazily from config.scope_types
---@type table<string, boolean>?
local scope_set

---@return table<string, boolean>
local function get_scope_set()
	if scope_set then
		return scope_set
	end
	scope_set = {}
	for _, t in ipairs(config.scope_types) do
		scope_set[t] = true
	end
	return scope_set
end

--- Invalidate the cached scope_set (call after config.setup).
function M.invalidate()
	scope_set = nil
end

---@class Beast.Treesitter.Scope
---@field node TSNode
---@field start_row number 0-indexed
---@field end_row number 0-indexed
---@field indent number indent level (columns)

--- Find the innermost scope node at a given position.
---@param bufnr number
---@param pos? {[1]: number, [2]: number} 0-indexed {row, col}; defaults to cursor
---@return Beast.Treesitter.Scope?
function M.get(bufnr, pos)
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
	-- stylua: ignore
	if not ok or not parser then return nil end

	if not pos then
		local cursor = vim.api.nvim_win_get_cursor(0)
		pos = { cursor[1] - 1, cursor[2] }
	end

	local node = vim.treesitter.get_node({ bufnr = bufnr, pos = pos })
	-- stylua: ignore
	if not node then return nil end

	local types = get_scope_set()

	-- Walk up to find the innermost scope-defining node
	while node do
		if types[node:type()] then
			local start_row, _, end_row, _ = node:range()
			return {
				node = node,
				start_row = start_row,
				end_row = end_row,
				indent = vim.fn.indent(start_row + 1),
			}
		end
		node = node:parent()
	end

	return nil
end

return M
