---Orchestrator around Frame. Produces WinResizeData[] for the public ops, plus
---merge/apply primitives shared by init.lua / autocmds.lua / animate.lua.
local Frame = require("beast.libs.window.frame")
local win = require("beast.libs.window.win")

local M = {}

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

---Focus-driven autowidth on the current window.
---@return Beast.Window.WinResizeData[]
function M.autowidth(curwin_id)
	local top = Frame.new()
	if top.type == "leaf" then
		return {}
	end
	if
		win.is_valid(curwin_id)
		and not win.is_floating(curwin_id)
		and not win.get_option(curwin_id, "winfixwidth")
		and not win.is_ignored(curwin_id)
	then
		local leaf = top:find_window(curwin_id)
		if not leaf then
			return {}
		end
		local wanted = win.get_wanted_width(curwin_id)
		if top:get_min_width(curwin_id, wanted) > top:get_width() then
			top:maximize_window(leaf, true, false)
		else
			top:autowidth(leaf)
		end
	else
		top:equalize_windows(true, false)
	end
	return top:get_data_for_width_resizing()
end

---@return Beast.Window.WinResizeData[] width, Beast.Window.WinResizeData[] height
function M.maximize_win(winid)
	local top = Frame.new()
	if top.type == "leaf" then
		return {}, {}
	end
	local leaf = top:find_window(winid)
	if not leaf then
		return {}, {}
	end
	top:maximize_window(leaf, true, true)
	return top:get_data_for_width_resizing(), top:get_data_for_height_resizing()
end

---@return Beast.Window.WinResizeData[]
function M.equalize_wins()
	local top = Frame.new()
	if top.type == "leaf" then
		return {}
	end
	top:equalize_windows(true, true)
	return M.merge(top:get_data_for_width_resizing(), top:get_data_for_height_resizing())
end

return M
