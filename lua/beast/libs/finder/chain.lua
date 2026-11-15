--- Chains: from the picker shown, a key opens the next one (a Level pushed on the Session) and the
--- back keys come back. The map of what leads where is `chains.lua`; the configuration (`chains`) chooses
--- which edges are on and which keys follow them.
local Level = require("beast.libs.finder.level")
local config = require("beast.libs.finder.config")
local edges = require("beast.libs.finder.chains")

local M = {}

--- The edge between two sources. Raises when the pair is not a built-in chain (a switched-off edge still exists).
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

--- The edges the configuration leaves on, each with the key that follows it (the configured one, else its own).
---@return Beast.Finder.Edge[]
function M.enabled()
	local configured = config.chains.edges
	local out = {}
	for _, edge in ipairs(edges) do
		local setting = configured[edge.id]
		if setting ~= false then
			out[#out + 1] = setmetatable({ key = setting and setting.key or edge.key }, { __index = edge })
		end
	end
	return out
end

--- The enabled edges that leave a source.
---@param from Beast.Finder.Source
---@return Beast.Finder.Edge[]
function M.from(from)
	return vim.tbl_filter(function(edge)
		return edge.from == from
	end, M.enabled())
end

--- The enabled edge a key follows from a source, if any.
---@param from Beast.Finder.Source
---@param key string
---@return Beast.Finder.Edge?
function M.find(from, key)
	for _, edge in ipairs(M.from(from)) do
		if M.same_key(edge.key, key) then
			return edge
		end
	end
end

--- The keys a picker opened on `root` needs: those of every enabled edge it can reach from there (each once).
---@param session Beast.Finder.Session
---@return string[]
function M.keys(session)
	local root = session.level.source.name
	local seen_key, seen_source, out = {}, { [root] = true }, {}
	local queue = { root }
	while #queue > 0 do
		for _, edge in ipairs(M.from(table.remove(queue, 1))) do
			local norm = M.normalize_key(edge.key)
			if not seen_key[norm] then
				seen_key[norm] = true
				out[#out + 1] = edge.key
			end
			if not seen_source[edge.to] then
				seen_source[edge.to] = true
				queue[#queue + 1] = edge.to
			end
		end
	end
	return out
end

--- `<c-g>` and `<C-g>` are the same key.
---@param key string
---@return string
function M.normalize_key(key)
	return vim.fn.keytrans(vim.keycode(key))
end

---@param a string
---@param b string
---@return boolean
function M.same_key(a, b)
	return M.normalize_key(a) == M.normalize_key(b)
end

--- Check the `chains` configuration. Raises, naming the problem, when it asks for something that cannot be:
--- an edge that is not built in, a key that is not a string or that another key of the picker already uses.
---@param cfg { back: string[], edges: table<string, false|{ key?: string }> }
function M.validate(cfg)
	local function fail(message)
		error("finder: chains: " .. message, 0)
	end
	local ids = {}
	for _, edge in ipairs(edges) do
		ids[#ids + 1] = edge.id
	end

	if type(cfg.back) ~= "table" or #cfg.back == 0 then
		fail("'back' must be a list of keys with at least one key")
	end
	local reserved = require("beast.libs.finder.keymaps").reserved()
	local taken = {} ---@type table<string, string> normalized key -> what uses it
	for _, key in ipairs(cfg.back) do
		if type(key) ~= "string" or key == "" then
			fail(("'back' has a key that is not a string: %s"):format(vim.inspect(key)))
		end
		if reserved[M.normalize_key(key)] then
			fail(("back key '%s' is already used by the picker"):format(key))
		end
		taken[M.normalize_key(key)] = "back"
	end

	for id, setting in pairs(cfg.edges) do
		if not vim.tbl_contains(ids, id) then
			fail(("unknown chain '%s' (known: %s)"):format(id, table.concat(ids, ", ")))
		end
		if setting ~= false and (type(setting) ~= "table" or (setting.key ~= nil and (type(setting.key) ~= "string" or setting.key == ""))) then
			fail(("chain '%s' must be false or { key = \"<key>\" }, got %s"):format(id, vim.inspect(setting)))
		end
	end

	local per_source = {} ---@type table<string, table<string, string>>
	for _, edge in ipairs(M.enabled()) do
		local norm = M.normalize_key(edge.key)
		if reserved[norm] then
			fail(("chain '%s': key '%s' is already used by the picker"):format(edge.id, edge.key))
		end
		if taken[norm] == "back" then
			fail(("chain '%s': key '%s' is also a back key"):format(edge.id, edge.key))
		end
		local used = per_source[edge.from] or {}
		per_source[edge.from] = used
		if used[norm] then
			fail(("chains '%s' and '%s' both use '%s' from '%s'"):format(used[norm], edge.id, edge.key, edge.from))
		end
		used[norm] = edge.id
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
---@param key string the key that was pressed
---@return boolean pushed
function M.drill(session, key)
	local from = session.level.source.name
	local edge = M.find(from, key)
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
	local ctx = context(session)
	for _, edge in ipairs(M.from(session.level.source.name)) do
		local text = edge.hint(ctx)
		if text then
			if #chunks > 0 then
				chunks[#chunks + 1] = { "   ", "BeastFinderHint" }
			end
			chunks[#chunks + 1] = { edge.key, "BeastFinderHintKey" }
			chunks[#chunks + 1] = { " " .. text, "BeastFinderHint" }
		end
	end
	if #session.stack > 0 and session.level.crumb then
		if #chunks > 0 then
			chunks[#chunks + 1] = { "   ", "BeastFinderHint" }
		end
		chunks[#chunks + 1] = { config.chains.back[1], "BeastFinderHintKey" }
		chunks[#chunks + 1] = { " back to " .. session.level.crumb, "BeastFinderHint" }
	end
	return #chunks > 0 and chunks or nil
end

return M
