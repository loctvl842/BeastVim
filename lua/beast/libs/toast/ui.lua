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
	local buf = View.buf.new("beast-toast")

	local width, height = record:dimensions()

	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		anchor = "SE",
		row = bottom_row,
		col = vim.o.columns - config.padding_right,
		width = width,
		height = height,
		style = "minimal",
		border = "none",
		focusable = false,
		zindex = 200,
		noautocmd = true,
	})
	View.win.wo(win, "wrap", false)
	View.win.wo(win, "winhl", "Normal:BeastToastNormal")
	View.win.wo(win, "winblend", 100) -- start transparent; fade_in animates to 0

	local ns = vim.api.nvim_create_namespace("beastvim_toast_" .. record.id)
	return ToastView(buf, win, ns, record)
end

---@param view Beast.Toast.View
function M.render(view)
	-- stylua: ignore
	if not view:is_valid() then return end

	local r = view.record

	local title_str = r.title or ""
	local title_w = (title_str ~= "" and (1 + vim.fn.strdisplaywidth(title_str)) or 0)
	local icon_str = r.icon or ""
	local icon_w = (icon_str ~= "" and (1 + vim.fn.strdisplaywidth(icon_str)) or 0)
	local width, _ = r:dimensions()
	local inner_w = math.max(0, width - (title_w + icon_w))

	-- Build the body (fitted text + per-segment paint list).
	-- segs_painted: { { hl, start_byte, end_byte } } applied after the line is set.
	local body_text, segs_painted = "", {}
	if r.segments then
		local remaining = inner_w
		for _, seg in ipairs(r.segments) do
			-- stylua: ignore
			if remaining <= 0 then break end
			local fit = trim_to_width(seg.text or "", remaining)
			local fit_w = vim.fn.strdisplaywidth(fit)
			if fit_w > 0 then
				local start_byte = #body_text
				body_text = body_text .. fit
				segs_painted[#segs_painted + 1] = { seg.hl or "BeastToastBody", start_byte, #body_text }
				remaining = remaining - fit_w
			end
		end
	else
		body_text = trim_to_width(config.normalize_message(r.message), inner_w)
	end

	-- Float width may need to grow/shrink for in-place updates (e.g. progress toasts).
	local cur = vim.api.nvim_win_get_config(view.win)
	if cur.width ~= width then
		pcall(vim.api.nvim_win_set_config, view.win, {
			relative = "editor",
			anchor = "SE",
			row = cur.row,
			col = cur.col,
			width = width,
			height = 1,
		})
	end

	local body_w = vim.fn.strdisplaywidth(body_text)
	local pad = math.max(0, inner_w - body_w)
	local line = body_text .. string.rep(" ", pad)
	if title_str ~= "" then
		line = line .. " " .. title_str
	end
	if icon_str ~= "" then
		line = line .. " " .. icon_str
	end
	pcall(vim.api.nvim_buf_set_lines, view.buf, 0, -1, false, { line })

	-- Apply highlights.
	local ns = vim.api.nvim_create_namespace("beastvim_toast_hl")
	vim.api.nvim_buf_clear_namespace(view.buf, ns, 0, -1)

	if r.segments then
		for _, p in ipairs(segs_painted) do
			vim.api.nvim_buf_set_extmark(view.buf, ns, 0, p[2], { end_row = 0, end_col = p[3], hl_group = p[1] })
		end
	else
		local body_bytes = #body_text + pad
		if body_bytes > 0 then
			local body_hl = r.dim and "Comment" or "BeastToastBody"
			vim.api.nvim_buf_set_extmark(view.buf, ns, 0, 0, { end_row = 0, end_col = body_bytes, hl_group = body_hl })
		end
	end

	local hl_title = "BeastToastTitle" .. r.level
	local col = #body_text + pad
	if title_str ~= "" then
		local tbytes = #(" " .. title_str)
		vim.api.nvim_buf_set_extmark(view.buf, ns, 0, col, { end_row = 0, end_col = col + tbytes, hl_group = hl_title })
		col = col + tbytes
	end

	if icon_str ~= "" then
		local ibytes = #(" " .. icon_str)
		vim.api.nvim_buf_set_extmark(view.buf, ns, 0, col, { end_row = 0, end_col = col + ibytes, hl_group = hl_title })
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
		col = vim.o.columns - config.padding_right,
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
