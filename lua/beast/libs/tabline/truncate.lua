local config = require("beast.libs.tabline.config")

local M = {}

--- Fast display-width: use byte length for ASCII, fallback for multibyte.
---@param s string
---@return integer
local function displaywidth(s)
	-- stylua: ignore
	if not s:find("[\128-\255]") then return #s end
	return vim.fn.strdisplaywidth(s)
end

--- Estimate the display width of a single buffer cell.
--- Uses ctx.diag_by_buf[bufnr] ~= nil as a binary check (no count/severity needed).
---@param bufnr integer
---@param ctx Beast.Tabline.Context
---@param is_anchor boolean Whether this is the anchor (active) buffer
---@return integer width Estimated cell width in columns
function M.estimate_cell_width(bufnr, ctx, is_anchor)
	local display_name = ctx.names_by_buf[bufnr] or "[No Name]"
	local name_w = math.min(displaywidth(display_name), config.max_name_width)
	local icon_w = 2 -- icon + space
	local pads = 2 -- left + right padding
	local inter = 1 -- inter-buffer space

	-- Status: diagnostic or modified indicator (~2 cols if present)
	local has_diag = ctx.diag_by_buf[bufnr] ~= nil
	local status_w = (has_diag or ctx.modified_by_buf[bufnr]) and 2 or 0

	-- Close button: only on anchor (active) buffer
	local close_w = is_anchor and 2 or 0

	return math.max(icon_w + name_w + status_w + close_w + pads + inter, config.min_cell_width)
end

--- Smart truncation around the anchor buffer.
--- Port of the heirline utils.truncate_buffers algorithm.
--- Alternates adding buffers from right/left until available width is exhausted.
---@param before integer[] Buffers before the anchor (in display order)
---@param anchor integer The anchor (active) buffer
---@param after integer[] Buffers after the anchor (in display order)
---@param est_fn fun(bufnr: integer, is_anchor: boolean): integer Width estimator
---@param available integer Available width in columns
---@return integer[] visible Visible buffers in display order
---@return integer left_hidden Count of hidden buffers on the left
---@return integer right_hidden Count of hidden buffers on the right
function M.fit_around_anchor(before, anchor, after, est_fn, available)
	local visible = { anchor }
	local total_width = est_fn(anchor, true)

	before = vim.list_slice(before)
	after = vim.list_slice(after)
	local left_idx = #before
	local right_idx = 1

	local take_left = false -- Start with right
	while true do
		local added = false

		if take_left then
			if left_idx >= 1 then
				local w = est_fn(before[left_idx], false)
				if (total_width + w) <= available then
					table.insert(visible, 1, before[left_idx])
					left_idx = left_idx - 1
					total_width = total_width + w
					added = true
				end
			end
		else
			if right_idx <= #after then
				local w = est_fn(after[right_idx], false)
				if (total_width + w) <= available then
					table.insert(visible, after[right_idx])
					right_idx = right_idx + 1
					total_width = total_width + w
					added = true
				end
			end
		end

		-- If prioritized side was full, try the other side
		if not added then
			if take_left then
				if right_idx <= #after then
					local w = est_fn(after[right_idx], false)
					if (total_width + w) <= available then
						table.insert(visible, after[right_idx])
						right_idx = right_idx + 1
						total_width = total_width + w
						added = true
					end
				end
			else
				if left_idx >= 1 then
					local w = est_fn(before[left_idx], false)
					if (total_width + w) <= available then
						table.insert(visible, 1, before[left_idx])
						left_idx = left_idx - 1
						total_width = total_width + w
						added = true
					end
				end
			end
		end

		-- stylua: ignore
		if not added then break end
		take_left = not take_left
	end

	local left_hidden = math.max(0, left_idx)
	local right_hidden = math.max(0, #after - right_idx + 1)

	return visible, left_hidden, right_hidden
end

--- Get the non-name overhead of a cell (icon + pads + status + close).
--- Used by the anchor-overflow fallback to compute how much space the name gets.
---@param bufnr integer
---@param ctx Beast.Tabline.Context
---@param is_anchor boolean
---@return integer overhead
function M.cell_overhead(bufnr, ctx, is_anchor)
	local icon_w = 2
	local pads = 2
	local inter = 1
	local has_diag = ctx.diag_by_buf[bufnr] ~= nil
	local status_w = (has_diag or ctx.modified_by_buf[bufnr]) and 2 or 0
	local close_w = is_anchor and 2 or 0
	return icon_w + status_w + close_w + pads + inter
end

return M
