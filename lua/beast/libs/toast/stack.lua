local config = require("beast.libs.toast.config")
local ui = require("beast.libs.toast.ui")

local M = {}

-- =============================================================================
-- UTILS
-- =============================================================================

---Bottom edge row for the bottom-most toast (anchor="SE").
---Sits just above the cmdline / statusline.
---@return integer
local function base_row()
	local total = vim.o.lines
	local cmd = vim.o.cmdheight or 0
	local status = (vim.o.laststatus > 0) and 1 or 0
	return total - cmd - status - config.margin_bottom
end

---Compute bottom-edge rows for each view, stacking BOTTOM-UP.
---views[1] = oldest (highest on screen), views[#views] = newest (bottommost).
---@param views Beast.Toast.View[]
---@return integer[]
local function calc_rows(views)
	local rows = {}
	local cursor = base_row()
	local height = 1 -- currently, all toasts are the same height (1)
	for i = #views, 1, -1 do
		rows[i] = cursor
		cursor = cursor - height - config.gap
	end
	return rows
end

-- =============================================================================
-- MAIN
-- =============================================================================

---Recalculate and move all open views to their correct rows.
---@param state Beast.Toast.State
function M.reflow(state)
	local rows = calc_rows(state.views)
	for i, view in ipairs(state.views) do
		ui.move(view, rows[i])
	end
end

---(Re)start the auto-dismiss timer of a view; a merged repeat calls this again.
---@param state Beast.Toast.State
---@param view Beast.Toast.View
local function arm_timer(state, view)
	local record = view.record
	if view.timer and not view.timer:is_closing() then
		view.timer:stop()
		view.timer:close()
	end
	if record.timeout ~= false and record.timeout > 0 then
		view.timer = vim.defer_fn(function()
			M.remove(state, record.id)
		end, record.timeout)
	end
end

---@param state Beast.Toast.State
---@param record Beast.Toast.Record
local function show(state, record)
	local view = ui.create(record, base_row())
	table.insert(state.views, view)
	ui.render(view)
	M.reflow(state) -- shift existing toasts upward, place new one at bottom
	ui.fade_in(view)
	arm_timer(state, view)
end

---Open view or still-queued record that `record` repeats, if any.
---@param state Beast.Toast.State
---@param record Beast.Toast.Record
---@return Beast.Toast.View|Beast.Toast.Record|nil
local function find_match(state, record)
	for _, view in ipairs(state.views) do
		if not view.closing and view.record.mergeable and view.record.key == record.key then
			return view
		end
	end
	-- Queued, or already taken off the queue but not yet shown (see `drain`).
	if state.inflight and state.inflight.mergeable and state.inflight.key == record.key then
		return state.inflight
	end
	for _, queued in ipairs(state.queue) do
		if queued.mergeable and queued.key == record.key then
			return queued
		end
	end
end

---@param state Beast.Toast.State
function M.drain(state)
	if state.draining then
		return
	end

	local record = table.remove(state.queue, 1)
	if not record then
		return
	end

	state.draining = true
	state.inflight = record
	-- Always schedule: nvim_open_win is forbidden in fast events AND in
	-- textlock contexts (BufRead, CmdwinEnter, etc.). vim.in_fast_event()
	-- doesn't detect textlock, so guarding only there leaks E565.
	vim.schedule(function()
		state.inflight = nil
		show(state, record)
		vim.defer_fn(function()
			state.draining = false
			M.drain(state)
		end, config.stagger)
	end)
end

---Queue a toast to be shown with staggered delay.
---@param state Beast.Toast.State
---@param record Beast.Toast.Record
function M.push(state, record)
	local match = record.mergeable and find_match(state, record)
	if match then
		local target = match.record or match
		target.count = target.count + 1
		if match.record then -- an open view: show the new count, keep it alive
			arm_timer(state, match)
			ui.render(match)
			M.reflow(state)
		end
		return
	end
	table.insert(state.queue, record)
	M.drain(state)
end

---Re-render an existing toast in place (e.g. for live progress updates).
---No-op if the record has no open view (already dismissed or never shown).
---@param state Beast.Toast.State
---@param record Beast.Toast.Record
function M.update(state, record)
	local _, view = state:find(record.id)
	-- stylua: ignore
	if not view then return end
	view.record = record
	ui.render(view)
	M.reflow(state)
end

---Fade out one toast, close it, reflow the rest.
---@param state Beast.Toast.State
---@param id integer
function M.remove(state, id)
	local idx, view = state:find(id)
	-- stylua: ignore
	if not idx or not view or view.closing then return end
	view.closing = true
	if view.timer and not view.timer:is_closing() then
		view.timer:stop()
		view.timer:close()
	end

	ui.fade_out(view, function()
		local cur_idx = state:find(id)
		if cur_idx then
			table.remove(state.views, cur_idx)
		end
		ui.close(view)
		M.reflow(state)
	end)
end

---Close all open toasts.
---@param state Beast.Toast.State
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
