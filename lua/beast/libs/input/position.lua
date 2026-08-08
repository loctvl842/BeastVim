local View = require("beast.libs.view")

---@class Beast.Input.Position
local M = {}

---@class Beast.Input.Position.Result
---@field mode "cursor"|"center"
---@field anchor? "NW"|"SW" -- only set when mode == "cursor"; NW grows down, SW grows up

--- Decide where the input box should be anchored: to the cursor (preferring
--- above, flipping below when there's no room) when the current window is a
--- normal editable buffer, or a centered fallback when there's no meaningful
--- anchor (a floating/beast-owned window, or a special buffer like a
--- terminal, quickfix list, or another plugin's UI).
---@param box_height integer total float height in screen rows, including top/bottom border
---@return Beast.Input.Position.Result
function M.resolve(box_height)
	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_win_get_buf(win)

	if not View.win.is_normal(win) or vim.bo[buf].buftype ~= "" then
		return { mode = "center" }
	end

	local sp = vim.fn.screenpos(win, vim.fn.line("."), vim.fn.col("."))
	if not sp.row or sp.row <= 0 then
		return { mode = "center" }
	end

	local room_above = sp.row - 1
	if room_above >= box_height then
		return { mode = "cursor", anchor = "SW" }
	end
	return { mode = "cursor", anchor = "NW" }
end

return M
