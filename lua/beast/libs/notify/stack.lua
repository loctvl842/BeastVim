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

---Compute row for a new bottommost notification.
---@param state Beast.Notify.State
---@return integer
local function next_slot_row(state)
	if #state.views == 0 then
		return top_row()
	end

	local slots = calc_slots(state.views)
	local last_view = state.views[#state.views]
	local _, last_h = last_view.record:dimensions()
	return slots[#slots] + (last_h + 2)
end

-- =============================================================================
-- MAIN
-- =============================================================================

---Recalculate and move all open views to their correct rows.
---@param state Beast.Notify.State
function M.reflow(state)
	local slots = calc_slots(state.views)
	for i, view in ipairs(state.views) do
		ui.move(view, slots[i])
	end
end

---@param state Beast.Notify.State
---@param record Beast.Notify.Record
local function show(state, record)
	local slot_row = next_slot_row(state)
	local view = ui.create(record, slot_row)
	table.insert(state.views, view)
	ui.render(view)

	if record.timeout ~= false then
		local index = #state.views
		local bonus = math.floor(math.sqrt(index * index * index) * config.stagger)
		local timeout = record.timeout + bonus
		vim.defer_fn(function()
			M.remove(state, record.id)
		end, timeout)
	end
end

---@param state Beast.Notify.State
function M.drain(state)
	if state.draining then
		return
	end

	local record = table.remove(state.queue, 1)
	if not record then
		return
	end

	state.draining = true
	show(state, record)

	vim.defer_fn(function()
		state.draining = false
		M.drain(state)
	end, config.stagger)
end

---Queue a notification to be shown with staggered delay.
---@param state Beast.Notify.State
---@param record Beast.Notify.Record
function M.push(state, record)
	table.insert(state.queue, record)
	M.drain(state)
end

---Slide out one notification, close it when done.
---@param state Beast.Notify.State
---@param id integer
function M.remove(state, id)
	local idx, view = state:find(id)
	-- stylua: ignore
	if not idx then return end

	ui.slide_out(view, function()
		local cur_idx = state:find(id)
		if cur_idx then
			table.remove(state.views, cur_idx)
		end
		ui.close(view)
		M.reflow(state)
	end)
end

---Close all open notifications.
---@param state Beast.Notify.State
function M.dismiss(state)
	local ids = {}
	for _, v in ipairs(state.views) do
		ids[#ids + 1] = v.record.id
	end
	for _, id in ipairs(ids) do
		M.remove(state, id)
	end
end

return M
