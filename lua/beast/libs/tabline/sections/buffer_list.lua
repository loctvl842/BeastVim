local cell = require("beast.libs.tabline.sections.cell")
local config = require("beast.libs.tabline.config")
local name_mod = require("beast.libs.tabline.name")
local truncate = require("beast.libs.tabline.truncate")

local M = {}

--- Render the buffer list section of the tabline.
---@param ctx Beast.Tabline.Context
---@return string rendered
---@return integer[] visible_buffers
---@return integer left_hidden
---@return integer right_hidden
function M.render(ctx)
	local listed = ctx.listed_buffers
	-- stylua: ignore
	if #listed == 0 then return "", {}, 0, 0 end

	-- Find the anchor (effective active buffer, or first listed)
	local anchor = nil
	local anchor_idx = nil
	for i, bufnr in ipairs(listed) do
		if bufnr == ctx.effective_active then
			anchor = bufnr
			anchor_idx = i
			break
		end
	end
	if not anchor then
		anchor = listed[1]
		anchor_idx = 1
	end

	-- Available width for buffer list (no marker reserve — accounted for after truncation)
	local available = ctx.columns - (ctx.sidebar_width or 0) - ctx.tabpages_width

	-- Width estimator using ctx
	local function est_fn(bufnr, is_anchor)
		return truncate.estimate_cell_width(bufnr, ctx, is_anchor)
	end

	-- Split into before/after around anchor
	local before = vim.list_slice(listed, 1, anchor_idx - 1)
	local after = vim.list_slice(listed, anchor_idx + 1)

	local visible, left_hidden, right_hidden

	-- Anchor-overflow fallback: if anchor alone exceeds available width
	local anchor_width = est_fn(anchor, true)
	if anchor_width > available then
		-- Shrink anchor name to fit
		local overhead = truncate.cell_overhead(anchor, ctx, true)
		local max_name = math.max(1, available - overhead)
		-- Override the name in ctx for this render
		local original_name = ctx.names_by_buf[anchor]
		ctx.names_by_buf[anchor] = name_mod.truncate_text(original_name or "[No Name]", max_name)

		visible = { anchor }
		left_hidden = #before
		right_hidden = #after
	else
		-- First pass: try fitting everything without marker reserves
		visible, left_hidden, right_hidden = truncate.fit_around_anchor(before, anchor, after, est_fn, available)

		-- If truncation happened, re-run with marker width subtracted
		if left_hidden > 0 or right_hidden > 0 then
			local marker_w = 0
			if #before > 0 then
				marker_w = marker_w + config.truncation_marker_reserve
			end
			if #after > 0 then
				marker_w = marker_w + config.truncation_marker_reserve
			end
			visible, left_hidden, right_hidden = truncate.fit_around_anchor(before, anchor, after, est_fn, available - marker_w)
		end
	end

	local parts = {}

	-- Left truncation marker
	if left_hidden > 0 then
		table.insert(parts, "%#BeastTlTruncMarker# " .. left_hidden .. " … ")
	end

	-- Render visible buffer cells
	for _, bufnr in ipairs(visible) do
		table.insert(parts, cell.render(bufnr, ctx))
	end

	-- Right truncation marker
	if right_hidden > 0 then
		table.insert(parts, "%#BeastTlTruncMarker# " .. right_hidden .. " … ")
	end

	return table.concat(parts), visible, left_hidden, right_hidden
end

return M
