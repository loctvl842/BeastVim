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
	for i = #views, 1, -1 do
		rows[i] = cursor
		cursor = cursor - (views[i].height or 1) - config.gap
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

---@param state Beast.Toast.State
---@param record Beast.Toast.Record
local function show(state, record)
	local view = ui.create(record, base_row())
	table.insert(state.views, view)
	ui.render(view)
	M.reflow(state) -- shift existing toasts upward, place new one at bottom
	ui.fade_in(view)

	if record.timeout ~= false and record.timeout > 0 then
		vim.defer_fn(function()
			M.remove(state, record.id)
		end, record.timeout)
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
	show(state, record)

	vim.defer_fn(function()
		state.draining = false
		M.drain(state)
	end, config.stagger)
end

---Queue a toast to be shown with staggered delay.
---@param state Beast.Toast.State
---@param record Beast.Toast.Record
function M.push(state, record)
	table.insert(state.queue, record)
	M.drain(state)
end

---Fade out one toast, close it, reflow the rest.
---@param state Beast.Toast.State
---@param id integer
function M.remove(state, id)
	local idx, view = state:find(id)
	-- stylua: ignore
	if not idx then return end

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
