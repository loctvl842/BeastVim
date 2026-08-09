local View = require("beast.libs.view")
local config = require("beast.libs.select.config")
local filter = require("beast.libs.select.filter")
local list = require("beast.libs.select.list")

---@class Beast.Select.UI
local M = {}

local MAX_VISIBLE_ITEMS = 15
local WIDTH_RATIO = 0.5
local MIN_WIDTH = 40
local MAX_WIDTH = 90
local DEBOUNCE_MS = 30

--- Wraps a raw item with its original 1-based index, so filtering (which
--- narrows `items` to a subset) never loses the index the native
--- `vim.ui.select` contract must report back to `on_choice`.
---@class Beast.Select.Wrapped
---@field value any
---@field idx integer

---@param prompt string already defaulted to "Select one of:" by init.lua
---@return string
local function format_title(prompt)
	local trimmed = vim.trim(prompt):gsub(":$", "")
	return " " .. trimmed .. " "
end

---@param footer_hints? { key: string, label: string }[]
---@return string
local function format_footer(footer_hints)
	local parts = { "Confirm enter   Cancel esc" }
	for _, hint in ipairs(footer_hints or {}) do
		parts[#parts + 1] = hint.label .. " " .. hint.key
	end
	return " " .. table.concat(parts, "   ") .. " "
end

---@class Beast.Select.Opts
---@field prompt string
---@field format_item fun(item: any): string
---@field kind? string
---@field format_tag? fun(item: any): string?
---@field footer_hints? { key: string, label: string }[]

--- Open the picker. `items`/`opts`/`on_choice` follow the native
--- `vim.ui.select` contract; `opts.format_tag`/`opts.footer_hints` are
--- BeastVim-specific extensions (see PM spec Behavior Rules) — third-party
--- plugins that only pass native opts fields simply don't get them.
---@param items any[]
---@param opts Beast.Select.Opts
---@param on_choice fun(item: any?, idx: integer?)
function M.open(items, opts, on_choice)
	local total_w = math.min(math.max(math.floor(vim.o.columns * WIDTH_RATIO), MIN_WIDTH), MAX_WIDTH)
	local content_w = total_w - 2
	local list_h = math.max(1, math.min(#items, MAX_VISIBLE_ITEMS))
	local total_h = list_h + 4
	-- Upper-middle, not dead-center (matches input's centered-fallback
	-- placement) — but never let a tall list run off the bottom of a small
	-- terminal.
	local top = math.max(0, math.min(math.floor(vim.o.lines / 4), vim.o.lines - total_h - 1))
	local left = math.floor((vim.o.columns - total_w) / 2)

	local backdrop_buf = View.buf.new("beast-select-backdrop")
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
	View.win.wo(backdrop_win, "winhighlight", "Normal:BeastSelectBackdrop,EndOfBuffer:BeastSelectBackdrop")
	View.win.wo(backdrop_win, "winblend", config.ui.backdrop)

	local input_buf = View.buf.new("beast-select-input")
	vim.bo[input_buf].buftype = "prompt"
	vim.fn.prompt_setprompt(input_buf, "")

	local input_win = vim.api.nvim_open_win(input_buf, true, {
		relative = "editor",
		row = top,
		col = left,
		width = content_w,
		height = 1,
		style = "minimal",
		border = { "╭", "─", "╮", "│", "┤", "─", "├", "│" },
		title = format_title(opts.prompt),
		title_pos = "left",
		zindex = 101,
	})
	View.win.wo(input_win, "winhl", "Normal:BeastSelectInputNormal,FloatBorder:BeastSelectBorder,FloatTitle:BeastSelectInputTitle")
	vim.wo[input_win].cursorline = false
	vim.wo[input_win].number = false
	vim.wo[input_win].relativenumber = false
	vim.wo[input_win].signcolumn = "no"
	vim.wo[input_win].wrap = false

	local list_view = list.create(top + 3, left, content_w, list_h, nil, format_footer(opts.footer_hints))

	---@type Beast.Select.Wrapped[]
	local wrapped = {}
	for i, item in ipairs(items) do
		wrapped[i] = { value = item, idx = i }
	end

	---@param w Beast.Select.Wrapped
	local function format_item(w)
		return opts.format_item(w.value)
	end

	---@param w Beast.Select.Wrapped
	local function format_tag(w)
		return opts.format_tag(w.value)
	end

	local function render_filtered(query)
		local filtered = {}
		for _, w in ipairs(wrapped) do
			if filter.matches(opts.format_item(w.value), query) then
				filtered[#filtered + 1] = w
			end
		end
		list.render(list_view, filtered, format_item, opts.format_tag and format_tag or nil)
	end

	render_filtered("")

	local debounced = Util.debounce(DEBOUNCE_MS, function()
		local text = vim.api.nvim_buf_get_lines(input_buf, 0, 1, false)[1] or ""
		render_filtered(text)
	end)

	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		debounced:close()
		vim.cmd("stopinsert")
		if vim.api.nvim_win_is_valid(input_win) then
			vim.api.nvim_win_close(input_win, true)
		end
		if list_view:is_valid() then
			list_view:close()
		end
		if vim.api.nvim_win_is_valid(backdrop_win) then
			vim.api.nvim_win_close(backdrop_win, true)
		end
	end

	local function confirm()
		local w = list.selected(list_view)
		close()
		if w then
			on_choice(w.value, w.idx)
		else
			on_choice(nil, nil)
		end
	end

	local function cancel()
		if closed then
			return
		end
		close()
		on_choice(nil, nil)
	end

	vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
		buffer = input_buf,
		callback = function()
			debounced()
		end,
	})

	local map_opts = { buffer = input_buf, nowait = true, silent = true }
	vim.keymap.set("i", "<CR>", confirm, map_opts)
	vim.keymap.set("n", "<CR>", confirm, map_opts)
	vim.keymap.set("i", "<Esc>", cancel, map_opts)
	vim.keymap.set("n", "<Esc>", cancel, map_opts)
	vim.keymap.set("n", "q", cancel, map_opts)
	vim.keymap.set("i", "<C-j>", function()
		list.move(list_view, 1)
	end, map_opts)
	vim.keymap.set("i", "<Down>", function()
		list.move(list_view, 1)
	end, map_opts)
	vim.keymap.set("i", "<C-k>", function()
		list.move(list_view, -1)
	end, map_opts)
	vim.keymap.set("i", "<Up>", function()
		list.move(list_view, -1)
	end, map_opts)

	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = input_buf,
		once = true,
		callback = function()
			vim.schedule(cancel)
		end,
	})

	vim.cmd("startinsert!")
end

return M
