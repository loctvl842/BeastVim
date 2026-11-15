--- Chains: from the picker shown, `<C-g>` opens the next one (a Level pushed on the Session) and
--- `<BS>` / `<C-o>` come back. The map of what leads where is `chains.lua`.
local Level = require("beast.libs.finder.level")
local edges = require("beast.libs.finder.chains")

local M = {}

M.KEY = "<C-g>"

--- The edge between two sources. Raises when the pair is not a built-in chain.
---@param from Beast.Finder.Source
---@param to Beast.Finder.Source
---@return Beast.Finder.Edge
function M.edge(from, to)
	local known = {}
	for _, edge in ipairs(edges) do
		if edge.from == from and edge.to == to then
			return edge
		end
		if edge.from == from then
			known[#known + 1] = edge.to
		end
	end
	error(("finder: unsupported chain '%s -> %s' (from '%s': %s)"):format(from, to, from, #known > 0 and table.concat(known, ", ") or "none"), 2)
end

--- The edge a key follows from a source, if any.
---@param from Beast.Finder.Source
---@param key string
---@return Beast.Finder.Edge?
function M.find(from, key)
	for _, edge in ipairs(edges) do
		if edge.from == from and (edge.key or M.KEY) == key then
			return edge
		end
	end
end

--- What `drill` and the hint know about the picker shown. `with_items` also collects every matching
--- item (a walk over all of them: only when a chain is actually followed, never while drawing).
---@param session Beast.Finder.Session
---@param with_items? boolean
---@return Beast.Finder.ChainCtx
local function context(session, with_items)
	local level = session.level
	return {
		items = with_items and level.engine.matches(level.query) or nil,
		selected = require("beast.libs.finder.ui").list.selected(session.view.list),
		total = level.query.total,
		filter = level.query.filter,
	}
end

--- Open the next picker of the chain from the one shown. Says why (a message) when it cannot.
---@param session Beast.Finder.Session
---@return boolean pushed
function M.drill(session)
	local from = session.level.source.name
	local edge = M.find(from, M.KEY)
	if not edge then
		Toast("Nothing to open from here", vim.log.levels.INFO)
		return false
	end
	-- A change still waiting out its debounce has not been searched: the results are not the prompt's.
	if require("beast.libs.finder.ui").input.get_text(session.view.input) ~= session.level.query.filter.pattern then
		Toast("Still searching - try again in a moment", vim.log.levels.INFO)
		return false
	end
	local ctx = context(session, true)
	if not ctx.items then
		Toast("Still searching - try again in a moment", vim.log.levels.INFO)
		return false
	end
	local opened = #ctx.items > 0 and edge.open(ctx) or nil
	if type(opened) == "string" then
		Toast(opened, vim.log.levels.INFO)
		return false
	end
	if not opened then
		Toast("Nothing to open from here", vim.log.levels.INFO)
		return false
	end
	opened.crumb = edge.crumb
	session:push(Level.new(edge.to, opened))
	return true
end

--- Go back to the picker the chain came from.
---@param session Beast.Finder.Session
---@return boolean popped
function M.back(session)
	return session:pop()
end

--- The key hints under the picker: chunks of `{ text, highlight }`, or nil when there is nothing to say.
---@param session Beast.Finder.Session
---@return { [1]: string, [2]: string }[]?
function M.hint_text(session)
	local chunks = {}
	local edge = M.find(session.level.source.name, M.KEY)
	local text = edge and edge.hint(context(session))
	if text then
		chunks[#chunks + 1] = { M.KEY, "BeastFinderHintKey" }
		chunks[#chunks + 1] = { " " .. text, "BeastFinderHint" }
	end
	if #session.stack > 0 and session.level.crumb then
		if #chunks > 0 then
			chunks[#chunks + 1] = { "   ", "BeastFinderHint" }
		end
		chunks[#chunks + 1] = { "<BS>", "BeastFinderHintKey" }
		chunks[#chunks + 1] = { " back to " .. session.level.crumb, "BeastFinderHint" }
	end
	return #chunks > 0 and chunks or nil
end

return M
