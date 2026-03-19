local config = require("beast.libs.notify.config")
local ui = require("beast.libs.notify.ui")

local M = {}

-- =============================================================================
-- UTILS
-- =============================================================================

---First usable row, accounting for tabline.
---@return integer
local function top_row()
	local top = 0
	if vim.o.showtabline == 2 or (vim.o.showtabline == 1 and vim.fn.tabpagenr("$") > 1) then
		top = 1
	end
	return top
end

---Final col for all notification windows.
---@return integer
local function final_col()
	return vim.o.columns - config.width - 2
end

---Compute top-border row for each view, stacking top-down.
---views[1] = topmost (oldest), views[#] = bottommost (newest).
---@param views Beast.Notify.View[]
---@return integer[]
local function calc_slots(views)
	local slots = {}
	local cursor = top_row()
	for i = 1, #views do
		slots[i] = cursor
		local _, h = views[i].record:dimensions()
		cursor = cursor + (h + 2)
	end
	return slots
end

-- =============================================================================
-- MAIN
-- =============================================================================
---Open a new notification window and start its close timer.
---@param state Beast.Notify.State
---@param record Beast.Notify.Record
function M.push(state, record)
	local slot_row
	local _, h = record:dimensions()
	if #state.views == 0 then
		slot_row = top_row()
	else
		local slots = calc_slots(state.views)
		local last_view = state.views[#state.views]
		local _, last_h = last_view.record:dimensions()
		slot_row = slots[#slots] + (last_h + 2) -- below the current bottommost
	end

	local view = ui.create(record, slot_row)
	table.insert(state.views, view)
	ui.render(view)

	if record.timeout ~= false then
		vim.defer_fn(function()
			M.remove(state, record.id)
		end, record.timeout)
	end
end

---Slide out one notification, close it when done, reflow the rest immediately.
---@param state Beast.Notify.State
---@param id integer
function M.remove(state, id)
	local idx, view = state:find(id)
	-- stylua: ignore
	if not idx then return end

	-- Remove from array and reflow immediately so other windows
	-- fill the gap without waiting for the exit animation to finish.
	table.remove(state.views, idx)

	ui.close(view)
end

return M
