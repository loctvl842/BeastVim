local View = require("beast.libs.view")

---@class Beast.Input.UI
local M = {}

local MIN_WIDTH = 20
local MAX_WIDTH_RATIO = 0.6

---@param prompt string
---@param default? string
---@return integer
local function calc_width(prompt, default)
	local prompt_w = vim.fn.strdisplaywidth(prompt)
	local default_w = default and vim.fn.strdisplaywidth(default) or 0
	local max_width = math.floor(vim.o.columns * MAX_WIDTH_RATIO)
	return math.min(math.max(prompt_w + 4, default_w + 4, MIN_WIDTH), max_width)
end

---@param prompt? string
---@return string?
local function format_title(prompt)
	local trimmed = vim.trim(prompt or ""):gsub(":$", "")
  -- stylua: ignore
  if trimmed == "" then return nil end
	return " " .. trimmed .. " "
end

--- Attach confirm/cancel behavior to an already-open input window: pre-fills
--- the default text, wires <CR>/<Esc> and BufLeave-cancel, then enters insert
--- mode with the cursor at the end of the default text.
---@param buf integer
---@param win integer
---@param opts Beast.Input.Opts
---@param on_confirm fun(text: string?)
function M.attach(buf, win, opts, on_confirm)
	View.win.wo(win, "winhighlight", "Normal:BeastInputNormal,FloatBorder:BeastInputBorder,FloatTitle:BeastInputTitle")
	vim.wo[win].cursorline = false
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].wrap = false

	local has_default = opts.default and opts.default ~= ""
	if has_default then
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { opts.default })
	end

	local closed = false
	local function close()
    -- stylua: ignore
    if closed then return end
		closed = true
		vim.cmd("stopinsert")
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end

	local function confirm()
		local text = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
		close()
		on_confirm(text)
	end

	local function cancel()
    -- stylua: ignore
    if closed then return end
		close()
		on_confirm(nil)
	end

	local map_opts = { buffer = buf, nowait = true, silent = true }
	vim.keymap.set("i", "<CR>", confirm, map_opts)
	vim.keymap.set("n", "<CR>", confirm, map_opts)
	vim.keymap.set("i", "<Esc>", cancel, map_opts)
	vim.keymap.set("n", "<Esc>", cancel, map_opts)
	vim.keymap.set("n", "q", cancel, map_opts)

	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = buf,
		once = true,
		callback = function()
			vim.schedule(cancel)
		end,
	})

	vim.cmd(has_default and "startinsert!" or "startinsert")
end

--- Open the input as a centered, near-top overlay — used when there's no
--- meaningful cursor context to anchor to.
---@param opts Beast.Input.Opts
---@param on_confirm fun(text: string?)
function M.open_centered(opts, on_confirm)
	local width = calc_width(opts.prompt or "", opts.default)
	local row = math.floor(vim.o.lines / 4)
	local col = math.floor((vim.o.columns - width) / 2)

	local buf = View.buf.new("beast-input")
	local win_opts = {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = 1,
		style = "minimal",
		border = "rounded",
		zindex = 101,
	}
	local title = format_title(opts.prompt)
	if title then
		win_opts.title = title
		win_opts.title_pos = "left"
	end
	local win = vim.api.nvim_open_win(buf, true, win_opts)

	M.attach(buf, win, opts, on_confirm)
end

return M
