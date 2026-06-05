--[[
Frame layout tree built from `vim.fn.winlayout()`. Each node is one of:
  - 'leaf' (a single window, `self.winid` is set)
  - 'row'  (children laid out left-to-right; total width = sum + separators)
  - 'col'  (children laid out top-to-bottom; total height = sum + separators)

Ported from anuvyklack/windows.nvim/lib/frame.lua. The two upstream changes:
  * `middleclass` dropped → plain metatable class.
  * `Window` OO wrapper dropped → bare winid + functions from `beast.libs.window.win`.

`-1`/`+1` arithmetic throughout accounts for the single-cell separator between
sibling frames.
--]]

local win = require("beast.libs.window.win")
local list_extend = vim.list_extend

local function round(value)
	return math.floor(value + 0.5)
end

-- Width threshold for "breathing" suppression — windows within ±THRESHOLD of
-- their current width are left alone to avoid jittery 1-cell resizes.
local THRESHOLD = 1

---@class Beast.Window.WinResizeData
---@field winid integer
---@field width? integer
---@field height? integer

---@class Beast.Window.Frame
---@field type 'leaf'|'col'|'row'
---@field id string
---@field parent Beast.Window.Frame|nil
---@field children Beast.Window.Frame[]
---@field winid integer Only set when type == 'leaf'.
---@field new_width integer
---@field new_height integer
---@field _fixed_width boolean|nil
---@field _fixed_height boolean|nil
local Frame = {}
Frame.__index = Frame

---@param layout? table The result of `vim.fn.winlayout()`; defaults to current tab.
---@param id? string
---@param parent? Beast.Window.Frame
---@return Beast.Window.Frame
function Frame.new(layout, id, parent)
	layout = layout or vim.fn.winlayout()
	local self = setmetatable({}, Frame)
	self.id = id or "0"
	self.parent = parent

	if not parent then
		-- Top frame: total editor area. Cannot be resized by us.
		self.new_width = vim.o.columns
		self.new_height = vim.o.lines - vim.o.cmdheight - (vim.o.tabline ~= "" and 1 or 0) - 1
	end

	self.type = layout[1]
	if self.type == "leaf" then
		self.winid = layout[2]
	else
		local children = {}
		for i, l in ipairs(layout[2]) do
			children[i] = Frame.new(l, self.id .. i, self)
		end
		self.children = children
	end

	return self
end

---@param frame Beast.Window.Frame
---@return boolean
function Frame:equals(frame)
	return self.id == frame.id
end

-- =============================================================================
-- AUTOWIDTH
-- =============================================================================

---Calculate frame widths so that `curwinLeaf` gets its `wanted_width`,
---siblings shrink to `winminwidth`, fixed-width frames stay put.
---@param curwinLeaf Beast.Window.Frame
function Frame:autowidth(curwinLeaf)
	local curwin_id = curwinLeaf.winid
	local curwinFrame = self:get_child_with_frame(curwinLeaf)

	if self.type == "col" then
		local width = self.new_width
		for _, frame in ipairs(self.children) do
			frame.new_width = width
			if frame.type ~= "leaf" then
				if frame == curwinFrame then
					frame:autowidth(curwinLeaf)
				else
					frame:equalize_windows(true, false)
				end
			end
		end
	elseif self.type == "row" then
		local room = self.new_width
		local topFrame_leafs = self:get_longest_row()
		local totwincount = #topFrame_leafs

		for _, frame in ipairs(self.children) do
			if frame ~= curwinFrame and frame:is_fixed_width() then
				local width = frame:get_width()
				frame.new_width = width
				room = room - width - 1
				frame:equalize_windows(true, false)
				totwincount = totwincount - #frame:get_longest_row()
			end
		end

		local curwin_wanted_width = win.get_wanted_width(curwin_id)
		local wanted_width = curwinFrame:get_min_width(curwin_id, curwin_wanted_width)

		local n = #curwinFrame:get_longest_row()
		local N = totwincount
		local owed_width = round((room - N + 1) * n / N + n - 1)

		totwincount = totwincount - n

		local width = (wanted_width > owed_width) and wanted_width or owed_width

		if curwinFrame.type == "leaf" then
			local curwin_width = win.get_width(curwin_id)
			if curwin_width - THRESHOLD < width and width <= curwin_width + THRESHOLD then
				width = curwin_width
			end
		end

		curwinFrame.new_width = width
		room = room - width - 1
		if curwinFrame.type ~= "leaf" then
			curwinFrame:autowidth(curwinLeaf)
		end

		---@type Beast.Window.Frame[]
		local other_frames = {}
		for _, frame in ipairs(self.children) do
			if frame ~= curwinFrame and not frame:is_fixed_width() then
				table.insert(other_frames, frame)
			end
		end

		local Nf = #other_frames
		for i, frame in ipairs(other_frames) do
			if i == Nf then
				frame.new_width = room
			else
				local m = #frame:get_longest_row()
				local M_ = totwincount
				local w = round((room - M_ + 1) * m / M_ + m - 1)
				if frame.type == "leaf" then
					local win_width = win.get_width(frame.winid)
					if win_width - THRESHOLD < w and w <= win_width + THRESHOLD then
						w = win_width
					end
				end
				frame.new_width = w
				room = room - w - 1
				totwincount = totwincount - m
			end
			if frame.type ~= "leaf" then
				frame:equalize_windows(true, false)
			end
		end
	end
end

-- =============================================================================
-- MAXIMIZE
-- =============================================================================

---@param winLeaf Beast.Window.Frame
---@param do_width boolean
---@param do_height boolean
function Frame:maximize_window(winLeaf, do_width, do_height)
	if do_width then
		local topFrame_width = self:get_width()
		local topFrame_wanted_width = self:get_min_width(winLeaf.winid, topFrame_width)
		winLeaf.new_width = 2 * topFrame_width - topFrame_wanted_width
	end
	if do_height then
		local topFrame_height = self:get_height()
		local topFrame_wanted_height = self:get_min_height(winLeaf.winid, topFrame_height)
		winLeaf.new_height = 2 * topFrame_height - topFrame_wanted_height
	end

	local winFrame = winLeaf
	local parentFrame = winFrame.parent
	while parentFrame do
		if parentFrame.type == "col" then
			if do_height then
				local height = winFrame.new_height + #parentFrame.children - 1
				for _, frame in ipairs(parentFrame.children) do
					if frame ~= winFrame then
						if frame:is_fixed_height() then
							frame.new_height = frame:get_height()
						else
							local n = #frame:get_longest_column()
							frame.new_height = vim.o.winminheight * n + n - 1
						end
						height = height + frame.new_height
					end
				end
				parentFrame.new_height = height
			end

			if do_width then
				local width = winFrame.new_width
				parentFrame.new_width = width
				for _, frame in ipairs(parentFrame.children) do
					if frame ~= winFrame then
						frame.new_width = width
					end
				end
			end
		elseif parentFrame.type == "row" then
			if do_width then
				local width = winFrame.new_width + #parentFrame.children - 1
				for _, frame in ipairs(parentFrame.children) do
					if frame ~= winFrame then
						if frame:is_fixed_width() then
							frame.new_width = frame:get_width()
						else
							local n = #frame:get_longest_row()
							frame.new_width = vim.o.winminwidth * n + n - 1
						end
						width = width + frame.new_width
					end
				end
				parentFrame.new_width = width
			end

			if do_height then
				local height = winFrame.new_height
				parentFrame.new_height = height
				for _, frame in ipairs(parentFrame.children) do
					if frame ~= winFrame then
						frame.new_height = height
					end
				end
			end
		end

		for _, frame in ipairs(parentFrame.children) do
			if frame.type ~= "leaf" and frame ~= winFrame then
				frame:equalize_windows(do_width, do_height)
			end
		end

		winFrame = parentFrame
		parentFrame = parentFrame.parent
	end
end

-- =============================================================================
-- EQUALIZE
-- =============================================================================

---@param do_width boolean
---@param do_height boolean
function Frame:equalize_windows(do_width, do_height)
	if self.type == "col" then
		if do_height then
			local Nw = #self:get_longest_column()
			local room = self.new_height - #self.children + 1
			---@type Beast.Window.Frame[]
			local var = {}
			for _, frame in ipairs(self.children) do
				if frame:is_fixed_height() then
					frame.new_height = frame:get_height()
					room = room - frame.new_height - 1
					Nw = Nw - #frame:get_longest_column()
				else
					table.insert(var, frame)
				end
			end
			local Nf = #var
			for i, frame in ipairs(var) do
				if i == Nf then
					frame.new_height = room
				else
					local n = #frame:get_longest_column()
					local height = round(room * n / Nw + n - 1)
					Nw = Nw - n
					frame.new_height = height
					room = room - height
				end
			end
		end

		for _, frame in ipairs(self.children) do
			if do_width then
				frame.new_width = self.new_width
			end
			if frame.type ~= "leaf" then
				frame:equalize_windows(do_width, do_height)
			end
		end
	elseif self.type == "row" then
		if do_width then
			local Nw = #self:get_longest_row()
			local room = self.new_width - #self.children + 1
			---@type Beast.Window.Frame[]
			local var = {}
			for _, frame in ipairs(self.children) do
				if frame:is_fixed_width() then
					frame.new_width = frame:get_width()
					room = room - frame.new_width - 1
					Nw = Nw - #frame:get_longest_row()
				else
					table.insert(var, frame)
				end
			end
			local Nf = #var
			for i, frame in ipairs(var) do
				if i == Nf then
					frame.new_width = room
				else
					local n = #frame:get_longest_row()
					local width = round(room * n / Nw + n - 1)
					Nw = Nw - n
					frame.new_width = width
					room = room - width
				end
			end
		end

		for _, frame in ipairs(self.children) do
			if do_height then
				frame.new_height = self.new_height
			end
			if frame.type ~= "leaf" then
				frame:equalize_windows(do_width, do_height)
			end
		end
	end
end

-- =============================================================================
-- DATA EXTRACTION (for resize.apply)
-- =============================================================================

---@return Beast.Window.WinResizeData[]
function Frame:get_data_for_width_resizing()
	local r = {}
	for i, leaf in ipairs(self:get_leafs_for_width_resizing()) do
		r[i] = { winid = leaf.winid, width = leaf.new_width }
	end
	return r
end

---@return Beast.Window.WinResizeData[]
function Frame:get_data_for_height_resizing()
	local r = {}
	for i, leaf in ipairs(self:get_leafs_for_height_resizing()) do
		r[i] = { winid = leaf.winid, height = leaf.new_height }
	end
	return r
end

---@return Beast.Window.Frame[]
function Frame:get_leafs_for_width_resizing()
	local r = {}
	if self.type == "row" then
		local N = #self.children
		local add_last
		for i, frame in ipairs(self.children) do
			if i < N or add_last then
				local f = frame:get_direct_child_leaf()
				if f then
					table.insert(r, f)
				end
				if i == N - 1 then
					add_last = not f
				end
			end
			if frame.type ~= "leaf" then
				list_extend(r, frame:get_leafs_for_width_resizing())
			end
		end
	elseif self.type == "col" then
		for _, frame in ipairs(self.children) do
			if frame.type ~= "leaf" then
				list_extend(r, frame:get_leafs_for_width_resizing())
			end
		end
	else
		return { self }
	end
	return r
end

---@return Beast.Window.Frame[]
function Frame:get_leafs_for_height_resizing()
	local r = {}
	if self.type == "col" then
		local N = #self.children
		local add_last
		for i, frame in ipairs(self.children) do
			if i < N or add_last then
				local f = frame:get_direct_child_leaf()
				if f then
					table.insert(r, f)
				end
				if i == N - 1 then
					add_last = not f
				end
			end
			if frame.type ~= "leaf" then
				list_extend(r, frame:get_leafs_for_height_resizing())
			end
		end
	elseif self.type == "row" then
		for _, frame in ipairs(self.children) do
			if frame.type ~= "leaf" then
				list_extend(r, frame:get_leafs_for_height_resizing())
			end
		end
	else
		return { self }
	end
	return r
end

-- =============================================================================
-- FIXED-AXIS CLASSIFICATION (cached on top frame, propagated down)
-- =============================================================================

---@return boolean
function Frame:is_fixed_width()
	if self._fixed_width == nil then
		local top = self
		while top.parent do
			top = top.parent
		end
		top:_mark_fixed_width()
	end
	return self._fixed_width
end

---@return boolean
function Frame:is_fixed_height()
	if self._fixed_height == nil then
		local top = self
		while top.parent do
			top = top.parent
		end
		top:_mark_fixed_height()
	end
	return self._fixed_height
end

function Frame:_mark_fixed_width()
	if self.type == "leaf" then
		if win.is_ignored(self.winid) then
			self._fixed_width = true
		else
			self._fixed_width = win.get_option(self.winid, "winfixwidth") or false
		end
	elseif self.type == "row" then
		self._fixed_width = true
		for _, frame in ipairs(self.children) do
			frame:_mark_fixed_width()
			if not frame._fixed_width then
				self._fixed_width = false
			end
		end
	else
		self._fixed_width = false
		for _, frame in ipairs(self.children) do
			frame:_mark_fixed_width()
			if frame._fixed_width then
				self._fixed_width = true
			end
		end
	end
end

function Frame:_mark_fixed_height()
	if self.type == "leaf" then
		if win.is_ignored(self.winid) then
			self._fixed_height = true
		else
			self._fixed_height = win.get_option(self.winid, "winfixheight") or false
		end
	elseif self.type == "row" then
		self._fixed_height = false
		for _, frame in ipairs(self.children) do
			frame:_mark_fixed_height()
			if frame._fixed_height then
				self._fixed_height = true
			end
		end
	else
		self._fixed_height = true
		for _, frame in ipairs(self.children) do
			frame:_mark_fixed_height()
			if not frame._fixed_height then
				self._fixed_height = false
			end
		end
	end
end

-- =============================================================================
-- TREE QUERIES
-- =============================================================================

---@param frame Beast.Window.Frame
---@return Beast.Window.Frame
---@return integer
function Frame:get_child_with_frame(frame)
	local n = #self.id
	assert(frame.id:sub(0, n) == self.id, "Frame does not contain seeking frame")
	local i = tonumber(frame.id:sub(n + 1, n + 1)) --[[@as integer]]
	return self.children[i], i
end

---@return Beast.Window.Frame[]
function Frame:get_longest_row()
	if self.type == "leaf" then
		return { self }
	elseif self.type == "row" then
		local out = {}
		for _, frame in ipairs(self.children) do
			list_extend(out, frame:get_longest_row())
		end
		return out
	else
		local out, N = {}, 0
		for _, frame in ipairs(self.children) do
			local list = frame:get_longest_row()
			if #list > N then
				out = list
				N = #list
			end
		end
		return out
	end
end

---@return Beast.Window.Frame[]
function Frame:get_longest_column()
	if self.type == "leaf" then
		return { self }
	elseif self.type == "col" then
		local out = {}
		for _, frame in ipairs(self.children) do
			list_extend(out, frame:get_longest_column())
		end
		return out
	else
		local out, N = {}, 0
		for _, frame in ipairs(self.children) do
			local col = frame:get_longest_column()
			if #col > N then
				out = col
				N = #col
			end
		end
		return out
	end
end

---@return integer
function Frame:get_width()
	if not self.parent then
		return self.new_width
	elseif self.type == "leaf" then
		return win.get_width(self.winid)
	elseif self.type == "row" then
		local width = 0
		for _, frame in ipairs(self.children) do
			width = width + frame:get_width()
		end
		return width + #self.children - 1
	else
		for _, frame in ipairs(self.children) do
			if frame.type == "leaf" then
				return win.get_width(frame.winid)
			end
		end
		return self.children[1]:get_width()
	end
end

---@return integer
function Frame:get_height()
	if not self.parent then
		return self.new_height
	elseif self.type == "leaf" then
		return win.get_height(self.winid)
	elseif self.type == "col" then
		local height = 0
		for _, frame in ipairs(self.children) do
			height = height + frame:get_height()
		end
		return height + #self.children - 1
	else
		for _, frame in ipairs(self.children) do
			if frame.type == "leaf" then
				return win.get_height(frame.winid)
			end
		end
		return self.children[1]:get_height()
	end
end

---@param tarwin? integer Target winid.
---@param tarwin_width? integer Width that tarwin will occupy; defaults to `winwidth`.
---@return integer
function Frame:get_min_width(tarwin, tarwin_width)
	if self.type == "leaf" then
		if self.winid == tarwin then
			return tarwin_width or vim.o.winwidth
		elseif self:is_fixed_width() then
			return self:get_width()
		else
			return vim.o.winminwidth
		end
	elseif self.type == "row" then
		local width = 0
		for _, frame in ipairs(self.children) do
			width = width + frame:get_min_width(tarwin, tarwin_width)
		end
		return width + #self.children - 1
	else
		local width = 0
		for _, frame in ipairs(self.children) do
			local w = frame:get_min_width(tarwin, tarwin_width)
			if w > width then
				width = w
			end
		end
		return width
	end
end

---@param tarwin? integer Target winid.
---@param tarwin_height? integer
---@return integer
function Frame:get_min_height(tarwin, tarwin_height)
	if self.type == "leaf" then
		if self.winid == tarwin then
			return tarwin_height or vim.o.winheight
		elseif self:is_fixed_height() then
			return self:get_height()
		else
			return vim.o.winminheight
		end
	elseif self.type == "col" then
		local height = 0
		for _, frame in ipairs(self.children) do
			height = height + frame:get_min_height(tarwin, tarwin_height)
		end
		return height + #self.children - 1
	else
		local height = 0
		for _, frame in ipairs(self.children) do
			local h = frame:get_min_height(tarwin, tarwin_height)
			if h > height then
				height = h
			end
		end
		return height
	end
end

---@param winid integer
---@return Beast.Window.Frame|nil
function Frame:find_window(winid)
	if self.type == "leaf" then
		if self.winid == winid then
			return self
		end
		return nil
	end
	for _, frame in ipairs(self.children) do
		local leaf = frame:find_window(winid)
		if leaf then
			return leaf
		end
	end
	return nil
end

---@return Beast.Window.Frame|nil
function Frame:get_direct_child_leaf()
	if self.type == "leaf" then
		return self
	end
	for _, frame in ipairs(self.children) do
		if frame.type == "leaf" then
			return frame
		end
	end
	return nil
end

---@return Beast.Window.Frame[]
function Frame:get_all_nested_leafs()
	if self.type == "leaf" then
		return { self }
	end
	local out = {}
	for _, frame in ipairs(self.children) do
		list_extend(out, frame:get_all_nested_leafs())
	end
	return out
end

return Frame
