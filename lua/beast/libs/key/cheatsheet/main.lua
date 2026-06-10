local View = require("beast.libs.view")
local api = require("beast.libs.key.api")
local config = require("beast.libs.key.config")

---@class Beast.Key.Cheatsheet.MainView : Beast.View.Instance
---@field ns integer
---@field backdrop Beast.View.Instance
---@overload fun(buf?: integer, win?: integer, ns: integer, backdrop: Beast.View.Instance): Beast.Key.Cheatsheet.MainView
local MainView = View:extend(
	---@param obj Beast.Key.Cheatsheet.MainView
	function(obj, ns, backdrop)
		obj.ns = ns
		obj.backdrop = backdrop
	end
)

local M = {}

---@return integer width
---@return integer height
---@return integer row
---@return integer col
local function calc_geometry()
	local width = math.floor(vim.o.columns * config.cheatsheet.width)
	local height = math.floor(vim.o.lines * config.cheatsheet.height)
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)
	return width, height, row, col
end

---@return Beast.Key.Cheatsheet.MainView
function M.create()
	local backdrop_buf = View.buf.new("beast-backdrop")
	local main_buf = View.buf.new("beast-key")
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

	View.win.wo(backdrop_win, "winblend", config.cheatsheet.backdrop)
	View.win.wo(backdrop_win, "winhighlight", "Normal:BeastKeyBackdrop")

	local width, height, row, col = calc_geometry()

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

	View.win.wo(main_win, "winhighlight", "Normal:BeastKeyNormal,FloatBorder:BeastKeyBorder,WinBar:BeastKeyWinBar,WinBarNC:BeastKeyWinBar")
	local title = " 🦁 Keymaps"
	View.win.wo(main_win, "winbar", "%#BeastKeyTitle# " .. title .. "%*")
	View.win.wo(main_win, "wrap", false)
	View.win.wo(main_win, "number", false)
	View.win.wo(main_win, "relativenumber", false)
	View.win.wo(main_win, "signcolumn", "no")
	return MainView(main_buf, main_win, vim.api.nvim_create_namespace("beast_key_cheatsheet_main"), View(backdrop_buf, backdrop_win))
end

---@param main Beast.Key.Cheatsheet.MainView
function M.layout(main)
  -- stylua: ignore
	if not main:is_valid() then return end

	if main.backdrop:is_valid() then
		vim.api.nvim_win_set_config(main.backdrop.win, {
			relative = "editor",
			row = 0,
			col = 0,
			width = vim.o.columns,
			height = vim.o.lines,
		})
	end

	local width, height, row, col = calc_geometry()
	vim.api.nvim_win_set_config(main.win, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
	})
end

---@param main Beast.Key.Cheatsheet.MainView
---@param lines Beast.Key.API.Line[]?
function M.render(main, lines)
  --stylua: ignore
  if not main:is_valid() then return end
	local lines_segments = lines or api.default()

	local rendered = {}
	local marks = {}
	local ns = main.ns
	local buf = main.buf
	for i, segs in ipairs(lines_segments) do
		local s, col = "", 0
		for _, seg in ipairs(segs) do
			if seg.hl then
				marks[#marks + 1] = { i - 1, col, col + #seg.text, seg.hl }
			end
			s = s .. seg.text
			col = col + #seg.text
		end
		rendered[i] = s
	end
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, rendered)
	vim.bo[buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	for _, m in ipairs(marks) do
		vim.api.nvim_buf_set_extmark(buf, ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
	end
end

---@param main Beast.Key.Cheatsheet.MainView|nil
function M.close(main)
  --stylua: ignore
  if not main then return end
	main.backdrop:close()
	main:close()
end

return M
