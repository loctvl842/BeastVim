--- Runs a source to completion with no picker UI, so `finder/init.lua` can
--- decide whether to open the picker at all (see `auto_select` sources).
---
--- A `generation` counter guards against a rapid re-trigger: starting a new
--- check makes any previous check's eventual callback a no-op, even if the
--- underlying request (e.g. an LSP round-trip) is still in flight and can't
--- itself be cancelled.

local M = {}

local generation = 0

---@param source Beast.Finder.ASource
---@param filter Beast.Finder.Filter
---@param on_done fun(items: Beast.Finder.Item[])
function M.check(source, filter, on_done)
	generation = generation + 1
	local my_generation = generation
	local items = {}

	source.get(filter, function(item)
		if my_generation ~= generation then
			return
		end
		if item == nil then
			on_done(items)
			return
		end
		items[#items + 1] = item
	end)
end

return M
