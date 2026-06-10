local View = require("beast.libs.view")
local config = require("beast.libs.confirm.config")

---@alias BeastConfirmAlign "left"|"center"|"right"

---@class Beast.Confirm.UI.MainView : Beast.View.Instance
---@field parsed Beast.Confirm.Parsed
---@field ns integer
---@field backdrop Beast.View.Instance
---@overload fun(buf?: integer, win?: integer, parsed: Beast.Confirm.Parsed, ns: integer, backdrop: Beast.View.Instance): Beast.Confirm.UI.MainView
local MainView = View:extend(
	---@param obj Beast.Confirm.UI.MainView
	function(obj, parsed, ns, backdrop)
		obj.parsed = parsed
		obj.ns = ns
		obj.backdrop = backdrop
	end
)

local HIDDEN_CURSOR = "a:block-BeastExplorerCursor"
local saved_cursor = nil

local KEY_LEFT = vim.api.nvim_replace_termcodes("<Left>", true, true, true)
local KEY_RIGHT = vim.api.nvim_replace_termcodes("<Right>", true, true, true)

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
local function button_text(label, width)
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

	for raw_line in (text .. "\n"):gmatch("(.-)\n") do
		if raw_line == "" then
			table.insert(lines, "")
		elseif display_width(raw_line) <= max_w then
			table.insert(lines, raw_line)
		else
			local cur = ""
			for word in raw_line:gmatch("%S+") do
				if #cur == 0 then
					cur = word
				elseif display_width(cur) + 1 + display_width(word) <= max_w then
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

---@param labels string[]
---@param btn_width integer
---@return string
local function build_button_bar(labels, btn_width)
	local gap = "  "
	local parts = {}
	for _, label in ipairs(labels) do
		parts[#parts + 1] = button_text(label, btn_width)
	end
	return table.concat(parts, gap)
end

---@param parsed Beast.Confirm.Parsed
---@return integer width
---@return integer height
---@return integer row
---@return integer col
---@return integer btn_width
local function calc_main_geometry(parsed)
	local labels = parsed.labels
	local opts = parsed.opts

	local max_label_w = 0
	for _, label in ipairs(labels) do
		max_label_w = math.max(max_label_w, display_width(label))
	end
	local btn_width = opts.button_width or (max_label_w + 2)

	local buttons_str = build_button_bar(labels, btn_width)

	local min_width = opts.min_width or 40
	local max_width = opts.max_width or math.min(80, vim.o.columns - 4)

	local title_width = display_width(parsed.msg)
	local desc_width = parsed.opts.description and display_width(parsed.opts.description) or 0
	local content_width = math.max(display_width(buttons_str), title_width, desc_width)
	local width = math.min(math.max(content_width + 4, min_width), max_width)
	local inner_width = width - 2

	-- If button bar overflows inner_width, expand width up to editor limit
	if display_width(buttons_str) > inner_width then
		width = math.min(display_width(buttons_str) + 4, vim.o.columns - 4)
	end

	local msg_lines = wrap_text(parsed.msg, width - 2)
	local desc_lines = {}
	if parsed.opts.description and parsed.opts.description ~= "" then
		desc_lines = wrap_text(parsed.opts.description, width - 2)
	end
	local total_msg_lines = #msg_lines + #desc_lines
	local height = total_msg_lines + 2 -- message + blank + buttons

	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	return width, height, row, col, btn_width
end

-- =============================================================================
-- MAIN VIEW
-- =============================================================================

local M = {}

---@param parsed Beast.Confirm.Parsed
---@return Beast.Confirm.UI.MainView
function M.create(parsed)
	local opts = parsed.opts
	opts.align = opts.align or "center"

	local backdrop_buf = View.buf.new("beast-backdrop")
	local main_buf = View.buf.new("beast-confirm")

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

	View.win.wo(backdrop_win, "winhighlight", "Normal:BeastConfirmBackdrop,EndOfBuffer:BeastConfirmBackdrop")
	View.win.wo(backdrop_win, "winblend", config.ui.backdrop)

	local width, height, row, col, btn_width = calc_main_geometry(parsed)
	-- Store computed btn_width back for render
	parsed.opts.button_width = btn_width

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

	View.win.wo(main_win, "winhighlight", "Normal:BeastConfirmNormal,FloatBorder:BeastConfirmBorder")
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

	return MainView(main_buf, main_win, parsed, vim.api.nvim_create_namespace("beast_confirm"), View(backdrop_buf, backdrop_win))
end

---@param main Beast.Confirm.UI.MainView
---@param selected integer
function M.render(main, selected)
	-- stylua: ignore
	if not main:is_valid() then return end

	local parsed = main.parsed
	local labels = parsed.labels
	local opts = parsed.opts
	local btn_width = opts.button_width or 12
	local align = opts.align or "center"
	local gap = "  "

	local ok, conf = pcall(vim.api.nvim_win_get_config, main.win)
	-- stylua: ignore
	if not ok then return end

	-- conf.width is the content width (border is drawn outside)
	local inner_width = conf.width

	local buttons_str = build_button_bar(labels, btn_width)
	local button_col = math.max(0, math.floor((inner_width - display_width(buttons_str)) / 2))

	local lines = {}
	local msg_lines = wrap_text(parsed.msg, inner_width)
	local desc_lines = {}
	if opts.description and opts.description ~= "" then
		desc_lines = wrap_text(opts.description, inner_width)
	end

	for _, text in ipairs(msg_lines) do
		lines[#lines + 1] = align_line(text, inner_width, align)
	end
	local desc_start_row = nil
	if #desc_lines > 0 then
		desc_start_row = #lines -- 0-based row for first desc line
		for _, text in ipairs(desc_lines) do
			lines[#lines + 1] = align_line(text, inner_width, align)
		end
	end

	lines[#lines + 1] = string.rep(" ", inner_width)

	local btn_line = string.rep(" ", button_col) .. buttons_str
	local btn_line_width = display_width(btn_line)
	if btn_line_width < inner_width then
		btn_line = btn_line .. string.rep(" ", inner_width - btn_line_width)
	end
	lines[#lines + 1] = btn_line

	vim.bo[main.buf].modifiable = true
	vim.api.nvim_buf_set_lines(main.buf, 0, -1, false, lines)
	vim.bo[main.buf].modifiable = false

	vim.api.nvim_buf_clear_namespace(main.buf, main.ns, 0, -1)

	-- Dim description lines
	if desc_start_row then
		for i = 0, #desc_lines - 1 do
			local row = desc_start_row + i
			vim.api.nvim_buf_set_extmark(main.buf, main.ns, row, 0, {
				end_row = row,
				end_col = #lines[row + 1],
				hl_group = "BeastConfirmDescription",
			})
		end
	end

	-- Highlight each button
	local btn_row = #msg_lines + #desc_lines + 1
	local col_offset = button_col

	for i, label in ipairs(labels) do
		local btn_str = button_text(label, btn_width)
		local btn_start = col_offset
		local btn_end = col_offset + display_width(btn_str)

		vim.api.nvim_buf_set_extmark(main.buf, main.ns, btn_row, btn_start, {
			end_col = btn_end,
			hl_group = selected == i and "BeastConfirmButtonActive" or "BeastConfirmButton",
		})

		col_offset = btn_end + display_width(gap)
	end
end

---@param main Beast.Confirm.UI.MainView
---@param selected integer
---@param hotkeys string[]
---@return integer -- 0=dismissed, 1..N = chosen index
function M.run_modal_loop(main, selected, hotkeys)
	local n = #main.parsed.labels

	while true do
		local ok, key = pcall(vim.fn.getcharstr)
		if not ok then
			return 0
		end

		if key == "\r" then
			return selected
		elseif key == "\027" or key == "\003" then -- Esc or Ctrl-C
			return 0
		elseif key == ":" then
			vim.api.nvim_feedkeys(":", "n", false)
			return 0
		elseif key:sub(1, 1) == "\x80" then
			-- Special keys (mouse, arrows)
			local pos = vim.fn.getmousepos()
			if pos.winid ~= 0 and pos.winid ~= main.win then
				return 0
			end
			if key == KEY_LEFT then
				selected = selected > 1 and selected - 1 or n
				M.render(main, selected)
				vim.cmd("redraw")
			elseif key == KEY_RIGHT then
				selected = selected < n and selected + 1 or 1
				M.render(main, selected)
				vim.cmd("redraw")
			end
		elseif key == "\t" then
			selected = selected < n and selected + 1 or 1
			M.render(main, selected)
			vim.cmd("redraw")
		else
			-- Check hotkey match first (case-insensitive, same as Neovim C source)
			local lower = key:lower()
			local hotkey_idx = nil
			for i, hk in ipairs(hotkeys) do
				if hk == lower then
					hotkey_idx = i
					break
				end
			end
			if hotkey_idx then
				return hotkey_idx
			end
			-- Fallback: h/l for navigation (only if not a hotkey)
			if key == "h" then
				selected = selected > 1 and selected - 1 or n
				M.render(main, selected)
				vim.cmd("redraw")
			elseif key == "l" then
				selected = selected < n and selected + 1 or 1
				M.render(main, selected)
				vim.cmd("redraw")
			end
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
