local View = require("beast.libs.view")

---@alias BeastConfirmAlign "left"|"center"|"right"

---@class Beast.Confirm.Opts
---@field title string
---@field min_width? integer
---@field max_width? integer
---@field default? integer -- 1=yes, 2=no
---@field yes_label? string
---@field no_label? string
---@field button_width? integer
---@field align? BeastConfirmAlign
---@field width? integer -- calculated state (DO NOT SET)
---@field height? integer -- calculated state (DO NOT SET)

---@class Beast.Confirm.UI.MainView : Beast.View
---@field opts Beast.Confirm.Opts
---@field ns integer
---@field backdrop Beast.View
local MainView = View:extend(function(obj, opts, ns, backdrop)
	obj.opts = opts
	obj.ns = ns
	obj.backdrop = backdrop
end)

local HIDDEN_CURSOR = "a:block-BeastExplorerCursor"
local saved_cursor = nil

-- =============================================================================
-- UTILS
-- =============================================================================

---@param text string
---@return integer
local function display_width(text)
	return vim.fn.strdisplaywidth(text)
end

---@param label string
---@param width integer
---@return string
local function button(label, width)
	local pad = math.max(0, width - display_width(label))
	local left = math.floor(pad / 2)
	local right = pad - left
	return string.rep(" ", left) .. label .. string.rep(" ", right)
end

---@param text string
---@param max_w integer
---@return string[]
local function wrap_text(text, max_w)
	local lines = {}

	-- Split by newline FIRST (preserve empty lines)
	for raw_line in (text .. "\n"):gmatch("(.-)\n") do
		-- If line is empty, keep it
		if raw_line == "" then
			table.insert(lines, "")
		elseif #raw_line <= max_w then
			table.insert(lines, raw_line)
		else
			local cur = ""
			for word in raw_line:gmatch("%S+") do
				if #cur == 0 then
					cur = word
				elseif #cur + 1 + #word <= max_w then
					cur = cur .. " " .. word
				else
					table.insert(lines, cur)
					cur = word
				end
			end
			if #cur > 0 then
				table.insert(lines, cur)
			end
		end
	end

	return lines
end

---@param text string
---@param width integer
---@param align BeastConfirmAlign?
---@return string
local function align_line(text, width, align)
	align = align or "center"

	local text_w = display_width(text)
	if text_w >= width then
		return text
	end

	local pad = width - text_w
	local left = 0
	local right = 0

	if align == "left" then
		left = 0
		right = pad
	elseif align == "right" then
		left = pad
		right = 0
	else
		left = math.floor(pad / 2)
		right = pad - left
	end

	return string.rep(" ", left) .. text .. string.rep(" ", right)
end

---@param opts Beast.Confirm.Opts
---@return integer width
---@return integer height
---@return integer row
---@return integer col
local function calc_main_geometry(opts)
	local yes_label = opts.yes_label or "Yes"
	local no_label = opts.no_label or "No"
	local button_width = opts.button_width or (math.max(display_width(yes_label), display_width(no_label)) + 2)
	local yes_btn = button(yes_label, button_width)
	local no_btn = button(no_label, button_width)
	local gap = "  "
	local buttons = yes_btn .. gap .. no_btn

	local min_width = opts.min_width or 40
	local max_width = opts.max_width or 60

	local title_width = display_width(opts.title)
	local content_width = math.max(display_width(buttons), title_width)
	local width = math.min(math.max(content_width + 4, min_width), max_width)
	local inner_width = width - 2

	local msg_lines = wrap_text(opts.title, inner_width)
	local height = #msg_lines + 2 -- message lines + blank + buttons

	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	opts.width = width
	opts.height = height
	opts.button_width = button_width

	return width, height, row, col
end

-- =============================================================================
-- MAIN VIEW
-- =============================================================================

local M = {}

---@param opts? Beast.Confirm.Opts
---@return Beast.Confirm.UI.MainView
function M.create(opts)
	opts = opts or {}
	opts.align = opts.align or "center"

	local backdrop_buf = Util.create_scratch_buf("beast-backdrop")
	local main_buf = Util.create_scratch_buf("beast-confirm")

	local backdrop_win = vim.api.nvim_open_win(backdrop_buf, false, {
		relative = "editor",
		row = 0,
		col = 0,
		width = vim.o.columns,
		height = vim.o.lines,
		style = "minimal",
		focusable = false,
		zindex = 100,
	})

	vim.wo[backdrop_win].winhighlight = "Normal:NormalFloat,EndOfBuffer:NormalFloat"
	Util.wo(backdrop_win, "winblend", 10)

	local width, height, row, col = calc_main_geometry(opts)

	local main_win = vim.api.nvim_open_win(main_buf, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		zindex = 101,
	})

	vim.wo[main_win].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"
	vim.wo[main_win].cursorline = false
	vim.wo[main_win].number = false
	vim.wo[main_win].relativenumber = false
	vim.wo[main_win].signcolumn = "no"
	vim.wo[main_win].foldcolumn = "0"
	vim.wo[main_win].spell = false
	vim.wo[main_win].wrap = false
	vim.wo[main_win].winfixbuf = true

	saved_cursor = vim.o.guicursor
	vim.o.guicursor = HIDDEN_CURSOR

	return MainView(
		main_buf,
		main_win,
		opts,
		vim.api.nvim_create_namespace("beast_confirm"),
		View(backdrop_buf, backdrop_win)
	)
end

---@param main Beast.Confirm.UI.MainView
---@param selected integer
function M.render(main, selected)
	if not main:is_valid() then
		return
	end

	if main.opts.width == nil then
		error("MainView must have width")
	end

	if main.opts.button_width == nil then
		error("MainView must have button width")
	end

	local inner_width = main.opts.width - 2
	local btn_width = main.opts.button_width

	local yes_label = main.opts.yes_label or "Remove"
	local no_label = main.opts.no_label or "Cancel"

	local yes_btn = button(yes_label, btn_width)
	local no_btn = button(no_label, btn_width)
	local gap = "  "
	local buttons = yes_btn .. gap .. no_btn

	local button_col = math.floor((inner_width - display_width(buttons)) / 2)
	if button_col < 0 then
		button_col = 0
	end

	local lines = {}
	local msg_lines = wrap_text(main.opts.title, inner_width)

	for _, text in ipairs(msg_lines) do
		lines[#lines + 1] = align_line(text, inner_width, main.opts.align)
	end

	lines[#lines + 1] = string.rep(" ", inner_width)

	local btn_line = string.rep(" ", button_col) .. buttons
	local btn_line_width = display_width(btn_line)
	if btn_line_width < inner_width then
		btn_line = btn_line .. string.rep(" ", inner_width - btn_line_width)
	end
	lines[#lines + 1] = btn_line

	vim.bo[main.buf].modifiable = true
	vim.api.nvim_buf_set_lines(main.buf, 0, -1, false, lines)
	vim.bo[main.buf].modifiable = false

	vim.api.nvim_buf_clear_namespace(main.buf, main.ns, 0, -1)

	local btn_row = #msg_lines + 1
	local yes_start = button_col
	local yes_end = yes_start + display_width(yes_btn)
	local no_start = yes_end + display_width(gap)
	local no_end = no_start + display_width(no_btn)

	vim.api.nvim_buf_set_extmark(main.buf, main.ns, btn_row, yes_start, {
		end_col = yes_end,
		hl_group = selected == 1 and "PmenuSel" or "Normal",
	})

	vim.api.nvim_buf_set_extmark(main.buf, main.ns, btn_row, no_start, {
		end_col = no_end,
		hl_group = selected == 2 and "PmenuSel" or "Normal",
	})
end

---@param main Beast.Confirm.UI.MainView
---@param selected integer
function M.run_modal_loop(main, selected)
	while true do
		local ok, key = pcall(vim.fn.getcharstr)
		if not ok then
			return true
		end

		if key:sub(1, 1) == "\x80" then
			local pos = vim.fn.getmousepos()
			if pos.winid ~= 0 and pos.winid ~= main.win then
				return true
			end
		elseif key == "h" then
			selected = 1
			M.render(main, selected)
			vim.cmd("redraw")
		elseif key == "l" then
			selected = 2
			M.render(main, selected)
			vim.cmd("redraw")
		elseif key == "\t" then
			selected = selected == 1 and 2 or 1
			M.render(main, selected)
			vim.cmd("redraw")
		elseif key == "\r" then
			return selected ~= 1
		elseif key == "\027" or key == "q" then
			return true
		elseif key == ":" then
			vim.api.nvim_feedkeys(":", "n", false)
			return true
		end
	end
end

---@param main Beast.Confirm.UI.MainView
function M.close(main)
	if saved_cursor then
		vim.o.guicursor = saved_cursor
	end

	if vim.api.nvim_win_is_valid(main.win) then
		vim.api.nvim_win_close(main.win, true)
	end

	if vim.api.nvim_win_is_valid(main.backdrop.win) then
		vim.api.nvim_win_close(main.backdrop.win, true)
	end
end

return M
