local View = require("beast.libs.view")
local animate = require("beast.libs.animate")
local config = require("beast.libs.toast.config")

---@class Beast.Toast.View : Beast.View
---@field ns integer
---@field record Beast.Toast.Record
local ToastView = View:extend(function(obj, ns, record)
	obj.ns = ns
	obj.record = record
end)

-- =============================================================================
-- UTILS
-- =============================================================================

---@param filetype string
---@return integer
local function create_scratch_buf(filetype)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = filetype
	return buf
end

---Trim to a display-width budget, append ellipsis if truncated.
---@param s string
---@param maxw integer
---@return string
local function trim_to_width(s, maxw)
	if vim.fn.strdisplaywidth(s) <= maxw then
		return s
	end
	local take = math.max(0, maxw - 1)
	return vim.fn.strcharpart(s, 0, take) .. "…"
end

-- =============================================================================
-- VIEW
-- =============================================================================

local M = {}

---@param record Beast.Toast.Record
---@param bottom_row integer  row of the bottom edge (SE anchor)
---@return Beast.Toast.View
function M.create(record, bottom_row)
	local buf = create_scratch_buf("beast-toast")

	local width, height = record:dimensions()

	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		anchor = "SE",
		row = bottom_row,
		col = vim.o.columns,
		width = width,
		height = height,
		style = "minimal",
		border = "none",
		focusable = false,
		zindex = 200,
		noautocmd = true,
	})
	Util.wo(win, "wrap", false)
	Util.wo(win, "winhl", "Normal:Normal")
	Util.wo(win, "winblend", 100) -- start transparent; fade_in animates to 0

	local ns = vim.api.nvim_create_namespace("beastvim_toast_" .. record.id)
	return ToastView(buf, win, ns, record)
end

---@param view Beast.Toast.View
function M.render(view)
	-- stylua: ignore
	if not view:is_valid() then return end

	local r = view.record

	local msg_str = config.normalize_message(r.message)
	local title_str = r.title or ""
	local title_w = (title_str ~= "" and (1 + vim.fn.strdisplaywidth(title_str)) or 0)
	local icon_str = r.icon or ""
	local icon_w = (icon_str ~= "" and (1 + vim.fn.strdisplaywidth(icon_str)) or 0)
	local width, _ = r:dimensions()
	local inner_w = math.max(0, width - (title_w + icon_w))
	local msg_fit = trim_to_width(msg_str, inner_w)

	local pad = math.max(0, inner_w - vim.fn.strdisplaywidth(msg_fit))
	local line = msg_fit .. string.rep(" ", pad)
	if title_str ~= "" then
		line = line .. " " .. title_str
	end
	if icon_str ~= "" then
		line = line .. " " .. icon_str
	end
	pcall(vim.api.nvim_buf_set_lines, view.buf, 0, -1, false, { line })

	-- Apply highlight
	local ns = vim.api.nvim_create_namespace("beastvim_toast_hl")
	local hl = config.hl[r.level] or config.hl.INFO
	vim.api.nvim_buf_clear_namespace(view.buf, ns, 0, -1)
	local msg_bytes = #msg_fit + pad
	if msg_bytes > 0 then
		local body_hl = r.dim and "Comment" or hl.body
		vim.api.nvim_buf_set_extmark(view.buf, ns, 0, 0, { end_row = 0, end_col = msg_bytes, hl_group = body_hl })
	end

	local col = msg_bytes
	if title_str ~= "" then
		local tbytes = #(" " .. title_str)
		vim.api.nvim_buf_set_extmark(view.buf, ns, 0, col, { end_row = 0, end_col = col + tbytes, hl_group = hl.title })
		col = col + tbytes
	end

	if icon_str ~= "" then
		local ibytes = #(" " .. icon_str)
		vim.api.nvim_buf_set_extmark(view.buf, ns, 0, col, { end_row = 0, end_col = col + ibytes, hl_group = hl.title })
	end
end

---@param view Beast.Toast.View
function M.close(view)
	view:close()
end

---@param view Beast.Toast.View
---@param bottom_row integer
function M.move(view, bottom_row)
	-- stylua: ignore
	if not view:is_valid() then return end
	pcall(vim.api.nvim_win_set_config, view.win, {
		relative = "editor",
		anchor = "SE",
		row = bottom_row,
		col = vim.o.columns,
	})
end

---@param view Beast.Toast.View
function M.fade_in(view)
	-- stylua: ignore
	if not view:is_valid() then return end
	local start_blend = vim.wo[view.win].winblend or 100
	animate.run(view.win, { blend = start_blend }, { blend = 0 }, config.anim_ms, nil, { blend_delay = 0 })
end

---@param view Beast.Toast.View
---@param on_done? fun()
function M.fade_out(view, on_done)
	if not view:is_valid() then
		if on_done then
			on_done()
		end
		return
	end
	local start_blend = vim.wo[view.win].winblend or 0
	animate.run(view.win, { blend = start_blend }, { blend = 100 }, config.anim_ms, on_done, { blend_delay = 0 })
end

return M
