local util = require("beast.libs.statusline.util")

-- The statusline has limited width. If all components render, they might overflow.
-- We need to drop the least important ones first

local M = {}

---Given visible items keyed by region, drop the lowest-priority items across all regions
---until the combined width fits within `available_width`.
---
---Strategy:
---  1. Pool every item across regions, tagged with their region.
---  2. Sort ascending by priority — lowest priority items are removed first.
---  3. Walk the sorted list, mark items as hidden until total width fits.
---  4. Reconstruct per-region item lists in original order, skipping hidden ones.
---
---@param regions table<string, Beast.Statusline.VisibleItem[]>
---@param available_width integer
---@param default_sep string
---@param default_priority integer
---@return table<string, Beast.Statusline.VisibleItem[]>
function M.fit(regions, available_width, default_sep, default_priority)
	local total = 0
	for _, items in pairs(regions) do
		total = total + util.total_width(items, default_sep)
	end

	-- stylua: ignore
	if total <= available_width then return regions end

	-- Build a flat list of (region_name, index_in_region, priority) sorted by priority asc.
	local pool = {}
	for region_name, items in pairs(regions) do
		for idx, item in ipairs(items) do
			pool[#pool + 1] = {
				region = region_name,
				idx = idx,
				priority = item.spec.priority or default_priority,
				width = util.fragments_width(item.fragments),
			}
		end
	end
	table.sort(pool, function(a, b)
		return a.priority < b.priority
	end)

	---@type table<string, table<integer, boolean>>
	local hidden = {}
	for region_name in pairs(regions) do
		hidden[region_name] = {}
	end

	-- Drop items until we fit. Each drop saves the item's width plus (approximately) one
	-- separator — we use default_sep width as the estimate; precise accounting would require
	-- recomputing total per drop, which is overkill for our component counts.
	local sep_w = default_sep and util.sep_width(default_sep) or 0
	for _, entry in ipairs(pool) do
		if total <= available_width then
			break
		end
		hidden[entry.region][entry.idx] = true
		total = total - entry.width - sep_w
	end

	-- Rebuild region lists preserving original order minus hidden items.
	local result = {}
	for region_name, items in pairs(regions) do
		local kept = {}
		for idx, item in ipairs(items) do
			if not hidden[region_name][idx] then
				kept[#kept + 1] = item
			end
		end
		result[region_name] = kept
	end
	return result
end

return M
