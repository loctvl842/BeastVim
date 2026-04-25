local View = require("beast.libs.view")
local config = require("beast.libs.notify.config")
local animate = require("beast.libs.animate")

---@class Beast.Notify.View : Beast.View
---@field ns integer
---@field record Beast.Notify.Record
local NotifView = View:extend(function(obj, ns, record)
	obj.ns = ns
	obj.record = record
end)

-- =============================================================================
-- UTILS
-- =============================================================================

---Final col for all notification windows.
---@return integer
local function final_col()
	return vim.o.columns - config.width - 2
end

-- =============================================================================
-- VIEW
-- =============================================================================

local M = {}

---@param record Beast.Notify.Record
---@param slot_row integer
---@return Beast.Notify.View
function M.create(record, slot_row)
	local buf = Util.create_scratch_buf("beast-notify")
	local width, height = record:dimensions()
	local hl = config.hl[record.level] or config.hl.INFO

	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		anchor = "NW",
		row = slot_row,
		col = final_col(), -- open at final position, fade_in handles opacity
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		focusable = true,
		zindex = 200,
		noautocmd = true,
	})
	Util.wo(win, "winhl", "Normal:" .. hl.body .. ",FloatBorder:" .. hl.title)
	Util.wo(win, "wrap", false)
	Util.wo(win, "winblend", 100) -- start transparent

	local ns = vim.api.nvim_create_namespace("beastvim_notify_" .. record.id)
	return NotifView(buf, win, ns, record)
end

---@param view Beast.Notify.View
function M.render(view)
	-- stylua: ignore
	if not view:is_valid() then return end

	local r = view.record
	local hl = config.hl[r.level] or config.hl.INFO
	local icon = config.icons[r.level] or "!"
	local title_left = icon .. "  " .. (r.title ~= "" and r.title or r.level)

	local msg = {}
	for i = 1, math.min(#r.message, config.max_height) do
		msg[i] = r.message[i]
	end

	local lines = {}
	vim.list_extend(lines, msg)

	vim.bo[view.buf].modifiable = true
	vim.api.nvim_buf_set_lines(view.buf, 2, -1, false, lines)
	vim.bo[view.buf].modifiable = false

	vim.api.nvim_buf_clear_namespace(view.buf, view.ns, 0, -1)
	-- extmark 1: virtual title shown on line 0
	vim.api.nvim_buf_set_extmark(view.buf, view.ns, 0, 0, {
		virt_text = { { " " .. title_left, hl.title } },
		virt_text_win_col = 0,
		priority = 10,
	})
	-- extmark 2: highlight a RANGE starting from line 2
	if #msg > 0 then
		vim.api.nvim_buf_set_extmark(view.buf, view.ns, 1, 0, {
			hl_group = hl.body,
			end_line = #msg,
			end_col = #msg[#msg],
			priority = 5,
		})
	end
end

---@param view Beast.Notify.View
function M.close(view)
	view:close()
end

---@param view Beast.Notify.View
---@param slot_row integer
function M.move(view, slot_row)
	-- stylua: ignore
	if not view:is_valid() then return end
	vim.api.nvim_win_set_config(view.win, {
		relative = "editor",
		row = slot_row,
		col = final_col(),
	})
end

---@param view Beast.Notify.View
---@param on_done? fun()
function M.slide_out(view, on_done)
	if not view:is_valid() then
		if on_done then
			on_done()
		end
		return
	end

	local ok, conf = pcall(vim.api.nvim_win_get_config, view.win)
	if not ok then
		if on_done then
			on_done()
		end
		return
	end

	local start_col = math.floor(tonumber(conf.col) or 0)
	local start_width = conf.width
	local start_blend = vim.wo[view.win].winblend or 0

	animate.run(
		view.win,
		{
			col = start_col,
			width = start_width,
			blend = start_blend,
		},
		{
			col = start_col + start_width - 1,
			width = 1,
			blend = 100,
		},
		config.anim_ms or 220,
		on_done,
		{
			blend_delay = 0.2,
		}
	)
end

---@param view Beast.Notify.View
function M.fade_in(view)
	if not view:is_valid() then
		return
	end

	local start_blend = vim.wo[view.win].winblend or 100
	local from, to = { blend = start_blend }, { blend = 0 }

	animate.run(view.win, from, to, config.anim_ms or 180, nil, { blend_delay = 0.2 })
end

return M
