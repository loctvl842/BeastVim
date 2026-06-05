---Thin orchestrator around Frame — produces WinResizeData[] for the three
---public operations: autowidth (focus-driven), maximize_win, equalize_wins.
local Frame = require("beast.libs.window.frame")

local M = {}

---@param curwin_id integer
---@return Beast.Window.WinResizeData[]
function M.autowidth(curwin_id)
	local topFrame = Frame.new()
	if topFrame.type == "leaf" then
		return {}
	end

	local win = require("beast.libs.window.win")
	if
		win.is_valid(curwin_id)
		and not win.is_floating(curwin_id)
		and not win.get_option(curwin_id, "winfixwidth")
		and not win.is_ignored(curwin_id)
	then
		local leaf = topFrame:find_window(curwin_id)
		if not leaf then
			return {}
		end
		local top_w = topFrame:get_width()
		local wanted = win.get_wanted_width(curwin_id)
		local need = topFrame:get_min_width(curwin_id, wanted)
		if need > top_w then
			topFrame:maximize_window(leaf, true, false)
		else
			topFrame:autowidth(leaf)
		end
	else
		topFrame:equalize_windows(true, false)
	end

	return topFrame:get_data_for_width_resizing()
end

---@param winid integer
---@param do_width boolean
---@param do_height boolean
---@return Beast.Window.WinResizeData[] width
---@return Beast.Window.WinResizeData[] height
function M.maximize_win(winid, do_width, do_height)
	local topFrame = Frame.new()
	if topFrame.type == "leaf" then
		return {}, {}
	end
	local leaf = topFrame:find_window(winid)
	if not leaf then
		return {}, {}
	end
	topFrame:maximize_window(leaf, do_width, do_height)
	return topFrame:get_data_for_width_resizing(), topFrame:get_data_for_height_resizing()
end

---@param do_width boolean
---@param do_height boolean
---@return Beast.Window.WinResizeData[]
function M.equalize_wins(do_width, do_height)
	assert(do_width or do_height, "No axis to equalize")
	local topFrame = Frame.new()
	if topFrame.type == "leaf" then
		return {}
	end
	topFrame:equalize_windows(do_width, do_height)

	local resize = require("beast.libs.window.resize")
	if do_width and not do_height then
		return topFrame:get_data_for_width_resizing()
	elseif do_height and not do_width then
		return topFrame:get_data_for_height_resizing()
	end
	return resize.merge(topFrame:get_data_for_width_resizing(), topFrame:get_data_for_height_resizing())
end

return M
