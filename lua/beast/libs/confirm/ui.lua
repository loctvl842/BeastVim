local View = require("beast.libs.view")

---@class Beast.Confirm.Opts
---@field title string
---@field min_width? integer
---@field max_width? integer
---@field default? integer -- 1=yes, 2=no
---@field yes_label? string
---@field no_label? string
---@field button_width? integer
---@field cb? fun(ok: boolean)
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

---@param filetype string
---@return integer
local function create_scratch_buf(filetype)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = filetype
	return buf
end

---@param label string
---@param width integer
---@return string
local function button(label, width)
	local pad = width - #label
	local left = math.floor(pad / 2)
	local right = pad - left
	return string.rep(" ", left) .. label .. string.rep(" ", right)
end

---@param text string
---@param max_w integer
---@return string[]
local function wrap_text(text, max_w)
	if #text <= max_w then
		return { text }
	end
	local lines = {}
	local cur = ""
	for word in text:gmatch("%S+") do
		if #cur == 0 then
			cur = word
		elseif #cur + 1 + #word <= max_w then
			cur = cur .. " " .. word
		else
			lines[#lines + 1] = cur
			cur = word
		end
	end
	if #cur > 0 then
		lines[#lines + 1] = cur
	end
	return lines
end

---@param opts Beast.Confirm.Opts
---@return integer width
---@return integer height
---@return integer row
---@return integer col
local function calc_main_geometry(opts)
	local yes_label, no_label = opts.yes_label or "Yes", opts.no_label or "No"
	local button_width = opts.button_width or (math.max(#yes_label, #no_label) + 2)
	local yes_btn, no_btn = button(yes_label, button_width), button(no_label, button_width)
	local gap = "  "
	local buttons = yes_btn .. gap .. no_btn

	local content_width = math.max(#buttons, #opts.title)
	local width = math.min(math.max(content_width + 4, 50), 60)
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
	local backdrop_buf = create_scratch_buf("beast-backdrop")
	local main_buf = create_scratch_buf("beast-confirm")
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
  --stylua: ignore
  if not main:is_valid() then return end
  -- stylua: ignore
  if main.opts.width == nil then error("MainView must have width") end
	local inner_width = main.opts.width - 2

  -- stylua: ignore
  if main.opts.button_width == nil then error("MainView must have button width") end
	---@type integer
	local btn_width = main.opts.button_width
	local yes_btn = button("Remove", btn_width)
	local no_btn = button("Cancel", btn_width)
	local gap = "  "
	local buttons = yes_btn .. gap .. no_btn
	local button_col = math.floor((inner_width - #buttons) / 2)
	if button_col < 0 then
		button_col = 0
	end
	local lines = {}
	local msg_lines = wrap_text(main.opts.title, inner_width)
	for _, text in ipairs(msg_lines) do
		local pad = math.floor((inner_width - #text) / 2)
		lines[#lines + 1] = string.rep(" ", pad) .. text .. string.rep(" ", math.max(0, inner_width - pad - #text))
	end
	lines[#lines + 1] = string.rep(" ", inner_width) -- blank separator
	local btn_line = string.rep(" ", button_col) .. buttons
	lines[#lines + 1] = btn_line .. string.rep(" ", math.max(0, inner_width - #btn_line))

	vim.bo[main.buf].modifiable = true
	vim.api.nvim_buf_set_lines(main.buf, 0, -1, false, lines)
	vim.bo[main.buf].modifiable = false

	vim.api.nvim_buf_clear_namespace(main.buf, main.ns, 0, -1)

	local btn_row = #msg_lines + 1 -- 0-indexed: msg lines + blank
	local yes_start = button_col
	local yes_end = yes_start + #yes_btn
	local no_start = yes_end + #gap
	local no_end = no_start + #no_btn

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
			-- stylua: ignore
			if not ok then return true end

		if key:sub(1, 1) == "\x80" then
			-- special key (mouse, arrows, fn-keys, …)
			-- only mouse events populate getmousepos(); winid == 0 means no mouse
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
		else
			-- do nothing
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
