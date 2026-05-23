--- Pure layout geometry calculation for the finder UI.
--- No state, no side effects — just computes window positions and sizes.
local config = require("beast.libs.finder.config")

---@class Beast.Finder.Layout.Geometry
---@field row integer
---@field col integer
---@field w integer
---@field h integer
---@field border? string[]

---@class Beast.Finder.Layout
---@field input Beast.Finder.Layout.Geometry
---@field list Beast.Finder.Layout.Geometry
---@field preview? Beast.Finder.Layout.Geometry

local M = {}

---@param has_preview boolean
---@return Beast.Finder.Layout
function M.calc(has_preview)
	local total_w = math.floor(vim.o.columns * config.width)
	local total_h = math.floor(vim.o.lines * config.height)
	local top = math.floor((vim.o.lines - total_h) / 2)
	local left = math.floor((vim.o.columns - total_w) / 2)

	if not has_preview then
		local content_w = total_w - 2 -- left + right border
		local input_h = 1
		local list_content_h = total_h - 4

		return {
			input = {
				row = top,
				col = left,
				w = content_w,
				h = input_h,
				border = { "╭", "─", "╮", "│", "┤", "─", "├", "│" },
			},
			list = {
				row = top + 3,
				col = left,
				w = content_w,
				h = list_content_h,
				border = { "", "", "", "│", "╯", "─", "╰", "│" },
			},
		}
	end

	-- Content widths (excluding borders)
	-- Left column gets (1 - preview_ratio) of the total content width
	-- Total content width = total_w - 3 (left border + middle separator + right border)
	local content_w = total_w - 3
	local left_content_w = math.floor(content_w * (1 - config.preview_ratio))
	local preview_content_w = content_w - left_content_w

	-- Vertical: total_h = top border + input(1) + separator + list content + bottom border
	-- total_h = 1 + 1 + 1 + list_h + 1 → list_h = total_h - 4
	local input_h = 1
	local list_content_h = total_h - 4
	-- Preview content = total_h - 2 (top + bottom border only)
	local preview_content_h = total_h - 2

	return {
		input = {
			row = top,
			col = left,
			w = left_content_w,
			h = input_h,
			border = { "╭", "─", "┬", "│", "┤", "─", "├", "│" },
		},
		list = {
			row = top + 3,
			col = left,
			w = left_content_w,
			h = list_content_h,
			border = { "", "", "", "│", "┘", "─", "╰", "│" },
		},
		preview = { row = top, col = left + left_content_w + 1, w = preview_content_w, h = preview_content_h },
	}
end

return M
