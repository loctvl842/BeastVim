---Apply/merge WinResizeData[] — the side-effecting tail of the layout pipeline.
local win = require("beast.libs.window.win")

local M = {}

---Merge width and height data lists by winid. Mutates `width_data` in place
---(matches windows.nvim behavior). Entries unique to `height_data` are appended.
---@param width_data Beast.Window.WinResizeData[]
---@param height_data Beast.Window.WinResizeData[]
---@return Beast.Window.WinResizeData[]
function M.merge(width_data, height_data)
	if vim.tbl_isempty(height_data) then
		return width_data
	end
	local index = {}
	for i, d in ipairs(width_data) do
		index[d.winid] = i
	end
	for _, d in ipairs(height_data) do
		local i = index[d.winid]
		if i then
			width_data[i].height = d.height
		else
			table.insert(width_data, { winid = d.winid, height = d.height })
		end
	end
	return width_data
end

---Apply resize data immediately (no animation). Per-entry pcall-safe.
---@param data Beast.Window.WinResizeData[]
function M.apply(data)
	for _, d in ipairs(data) do
		if d.width then
			win.set_width(d.winid, d.width)
		end
		if d.height then
			win.set_height(d.winid, d.height)
		end
	end
end

return M
