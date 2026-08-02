-- Custom treesitter query predicates.
--
-- Neovim core ships `eq?`/`any-of?`/`has-parent?`/etc. (and generically
-- negates any `#not-<pred>?` by inverting the base predicate's result), but
-- has no `kind-eq?`. The `ecma` query base (shared by javascript/typescript/
-- jsx/tsx via `; inherits:`) uses `#not-kind-eq?` in its `indents.scm`, so
-- without this registration those languages' indents query fails to resolve
-- that predicate and the affected patterns never match.
--
-- Mirrors nvim-treesitter's own `plugin/query_predicates.lua` (MIT).

local query = vim.treesitter.query

--- True when every node captured by `predicate[2]` has one of the node
--- types listed in the rest of `predicate`. Core's generic `not-` negation
--- then gives `#not-kind-eq?` for free.
---@param match table<integer, TSNode[]>
---@param predicate any[]
local function kind_eq(match, predicate)
	local nodes = match[predicate[2]]
	if not nodes or #nodes == 0 then
		return true
	end

	local types = { unpack(predicate, 3) }
	for _, node in ipairs(nodes) do
		if not vim.list_contains(types, node:type()) then
			return false
		end
	end
	return true
end

query.add_predicate("kind-eq?", function(match, _, _, predicate)
	return kind_eq(match, predicate)
end, { force = true })
