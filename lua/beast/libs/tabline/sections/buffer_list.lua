local cell = require("beast.libs.tabline.sections.cell")
local config = require("beast.libs.tabline.config")
local name_mod = require("beast.libs.tabline.name")
local truncate = require("beast.libs.tabline.truncate")

local M = {}

--- Display width of a truncation marker for N hidden buffers.
--- Left: " N <icon> "   Right: " <icon> N "
---@param count integer Number of hidden buffers (0 → no marker)
---@param side "left"|"right"
---@return integer
local function marker_width(count, side)
	-- stylua: ignore
	if count <= 0 then return 0 end
	local icon = side == "left" and config.left_trunc_icon or config.right_trunc_icon
	return 1 + #tostring(count) + 1 + vim.fn.strdisplaywidth(icon) + 1
end

--- Trim a cell's display name and mark it as edge-trimmed.
--- Uses trailing ellipsis for right-edge, leading ellipsis for left-edge.
---@param ctx Beast.Tabline.Context
---@param bufnr integer
---@param new_name_w integer Target display width for the name (≥ 1)
---@param side "left"|"right"
local function trim_cell_name(ctx, bufnr, new_name_w, side)
	local name = ctx.names_by_buf[bufnr] or "[No Name]"
	if side == "right" then
		ctx.names_by_buf[bufnr] = name_mod.truncate_text_end(name, new_name_w)
	else
		ctx.names_by_buf[bufnr] = name_mod.truncate_text(name, new_name_w)
	end
end

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

	-- Find the anchor (best buffer for truncation centering)
	local anchor = nil
	local anchor_idx = nil
	for i, bufnr in ipairs(listed) do
		if bufnr == ctx.anchor_bufnr then
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

	local visible, left_hidden, right_hidden, total_width

	-- Anchor-overflow fallback: if anchor alone exceeds available width
	local anchor_width = est_fn(anchor, true)
	if anchor_width > available then
		-- Shrink anchor name to fit
		local overhead = truncate.cell_overhead(anchor, ctx, true)
		local max_name = math.max(1, available - overhead)
		local original_name = ctx.names_by_buf[anchor]
		ctx.names_by_buf[anchor] = name_mod.truncate_text(original_name or "[No Name]", max_name)

		visible = { anchor }
		left_hidden = #before
		right_hidden = #after
	else
		-- Step A: Fit max cells with full available width (no reserve)
		visible, left_hidden, right_hidden, total_width = truncate.fit_around_anchor(before, anchor, after, est_fn, available)

		-- Step B–F: Edge-trim when truncation occurs
		if left_hidden > 0 or right_hidden > 0 then
			-- Step C: Exact marker widths
			local left_marker_w = marker_width(left_hidden, "left")
			local right_marker_w = marker_width(right_hidden, "right")

			-- Step D: Space to free
			local gap = available - total_width
			local need_to_trim = left_marker_w + right_marker_w - gap

			-- Edge-trimmed cells skip min_cell_width in cell.render (via ctx.edge_trim_bufs)
			ctx.edge_trim_bufs = {}

			-- Step E: Trim right edge cell
			if need_to_trim > 0 and right_hidden > 0 and #visible > 1 then
				local rightmost = visible[#visible]
				local cell_w = est_fn(rightmost, false)
				local overhead = truncate.cell_overhead(rightmost, ctx, false)
				local max_trimmable = cell_w - overhead - 1

				if max_trimmable >= need_to_trim then
					local name_w = math.min(vim.fn.strdisplaywidth(ctx.names_by_buf[rightmost] or "[No Name]"), config.max_name_width)
					trim_cell_name(ctx, rightmost, math.max(1, name_w - need_to_trim), "right")
					ctx.edge_trim_bufs[rightmost] = true
					need_to_trim = 0
				else
					table.remove(visible)
					right_hidden = right_hidden + 1
					right_marker_w = marker_width(right_hidden, "right")
					need_to_trim = left_marker_w + right_marker_w - (gap + cell_w)
					gap = gap + cell_w
				end
			end

			-- Step F: Trim left edge cell
			if need_to_trim > 0 and left_hidden > 0 and #visible > 1 then
				local leftmost = visible[1]
				local cell_w = est_fn(leftmost, false)
				local overhead = truncate.cell_overhead(leftmost, ctx, false)
				local max_trimmable = cell_w - overhead - 1

				if max_trimmable >= need_to_trim then
					local name_w = math.min(vim.fn.strdisplaywidth(ctx.names_by_buf[leftmost] or "[No Name]"), config.max_name_width)
					trim_cell_name(ctx, leftmost, math.max(1, name_w - need_to_trim), "left")
					ctx.edge_trim_bufs[leftmost] = true
					need_to_trim = 0
				else
					table.remove(visible, 1)
					left_hidden = left_hidden + 1
					left_marker_w = marker_width(left_hidden, "left")
					need_to_trim = left_marker_w + right_marker_w - (gap + cell_w)
					gap = gap + cell_w
				end
			end

			-- Step E/F repeat: handle rare cascade (marker grew after drop)
			if need_to_trim > 0 and #visible > 1 then
				local side = right_hidden > 0 and "right" or (left_hidden > 0 and "left" or nil)
				if side then
					local idx = side == "right" and #visible or 1
					local edge_buf = visible[idx]
					local cell_w = est_fn(edge_buf, false)
					local overhead = truncate.cell_overhead(edge_buf, ctx, false)
					local trim_amount = math.min(need_to_trim, cell_w - overhead - 1)
					if trim_amount > 0 then
						local name_w = math.min(vim.fn.strdisplaywidth(ctx.names_by_buf[edge_buf] or "[No Name]"), config.max_name_width)
						trim_cell_name(ctx, edge_buf, math.max(1, name_w - trim_amount), side)
						ctx.edge_trim_bufs[edge_buf] = true
					end
				end
			end

			-- Step G: Pull in one more hidden buffer as a compact edge cell.
			-- Compact rendering: 1 leading pad, no close button.
			-- Right-side: also skip separator (marker follows).
			-- Left-side: keep separator (next visible cell follows).
			do
				-- Recompute actual visible width (edge-trimmed cells skip min_cell_width)
				local vis_total = 0
				for _, bufnr in ipairs(visible) do
					if ctx.edge_trim_bufs[bufnr] then
						local oh = truncate.cell_overhead(bufnr, ctx, bufnr == anchor)
						local nw = vim.fn.strdisplaywidth(ctx.names_by_buf[bufnr] or "[No Name]")
						vis_total = vis_total + oh + nw
					else
						vis_total = vis_total + est_fn(bufnr, bufnr == anchor)
					end
				end

				local cur_lmw = marker_width(left_hidden, "left")
				local cur_rmw = marker_width(right_hidden, "right")
				local remaining = available - vis_total - cur_lmw - cur_rmw

				-- Try right side first, then left
				local pull_side = right_hidden > 0 and "right" or (left_hidden > 0 and "left" or nil)
				if remaining > 0 and pull_side then
					local next_buf, new_hidden
					if pull_side == "right" then
						next_buf = after[#after - right_hidden + 1]
						new_hidden = right_hidden - 1
					else
						next_buf = before[left_hidden]
						new_hidden = left_hidden - 1
					end

					local new_mw = marker_width(new_hidden, pull_side)
					local marker_savings = (pull_side == "right" and cur_rmw or cur_lmw) - new_mw
					local space_for_cell = remaining + marker_savings
					local overhead = truncate.cell_overhead(next_buf, ctx, false)
					local full_w = est_fn(next_buf, false)

					-- Compact: skip close(2) + 1 pad; right also skips sep(1)
					local compact_savings = pull_side == "right" and 4 or 3
					local effective_overhead = overhead - compact_savings

					if space_for_cell >= full_w then
						-- Fits at full size (including min_cell_width padding)
						if pull_side == "right" then
							table.insert(visible, next_buf)
							right_hidden = new_hidden
						else
							table.insert(visible, 1, next_buf)
							left_hidden = new_hidden
						end
					elseif space_for_cell >= effective_overhead + 1 then
						-- Fits as compact edge cell (below min_cell_width)
						local max_name_w = math.min(vim.fn.strdisplaywidth(ctx.names_by_buf[next_buf] or "[No Name]"), space_for_cell - effective_overhead)
						trim_cell_name(ctx, next_buf, max_name_w, pull_side)
						ctx.edge_trim_compact = ctx.edge_trim_compact or {}
						ctx.edge_trim_compact[next_buf] = pull_side
						if pull_side == "right" then
							table.insert(visible, next_buf)
							right_hidden = new_hidden
						else
							table.insert(visible, 1, next_buf)
							left_hidden = new_hidden
						end
					end
				end
			end
		end
	end

	local parts = {}

	-- Left truncation marker
	if left_hidden > 0 then
		table.insert(parts, "%#BeastTlTruncMarker# " .. left_hidden .. " " .. config.left_trunc_icon .. " ")
	end

	-- Render visible buffer cells
	for _, bufnr in ipairs(visible) do
		table.insert(parts, cell.render(bufnr, ctx))
	end

	-- Right truncation marker
	if right_hidden > 0 then
		table.insert(parts, "%#BeastTlTruncMarker# " .. config.right_trunc_icon .. " " .. right_hidden .. " ")
	end

	return table.concat(parts), visible, left_hidden, right_hidden
end

return M
