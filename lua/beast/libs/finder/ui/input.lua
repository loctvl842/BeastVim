local View = require("beast.libs.view")
local config = require("beast.libs.finder.config")

---@class Beast.Finder.InputView : Beast.View
---@field ns integer
---@field _timer integer|nil vim.defer_fn timer handle (opaque)
local InputView = View:extend(function(obj, ns)
	obj.ns = ns
	obj._timer = nil
end)

local M = {}

---@return integer width, integer height, integer row, integer col
local function calc_geometry(total_w, total_h, win_row, win_col)
	local w = math.floor(vim.o.columns * config.width)
	local h = 1
	local row = win_row
	local col = win_col
	return w, h, row, col
end

---@param on_change fun(text: string)
---@param total_w integer list+preview combined width
---@param total_h integer unused, kept for symmetry
---@param win_row integer top row of the picker layout
---@param win_col integer left col of the picker layout
---@return Beast.Finder.InputView
function M.create(on_change, total_w, total_h, win_row, win_col)
	local buf = Util.create_scratch_buf("beastvim-finder-input")
	vim.bo[buf].buftype = "prompt"
	vim.fn.prompt_setprompt(buf, "")

	local w, _, row, col = calc_geometry(total_w, total_h, win_row, win_col)
	local ns = vim.api.nvim_create_namespace("beastvim-finder-input")

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = w,
		height = 1,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = " Find ",
		title_pos = "left",
		zindex = config.zindex,
	})

	Util.wo(win, "cursorline", false)
	Util.wo(win, "winhl", "Normal:BeastFinderPrompt,FloatBorder:BeastFinderBorder,FloatTitle:BeastFinderBorder")

	local view = InputView(buf, win, ns)

	local debounce_ms = config.debounce.normal_ms
	vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
		buffer = buf,
		callback = function()
			-- stylua: ignore
			if view._timer then vim.fn.timer_stop(view._timer) end
			view._timer = vim.fn.timer_start(debounce_ms, function()
				view._timer = nil
				local text = M.get_text(view)
				on_change(text)
			end)
		end,
	})

	vim.cmd("startinsert!")

	return view
end

---@param view Beast.Finder.InputView
---@return string
function M.get_text(view)
	-- stylua: ignore
	if not view:is_valid() then return "" end
	local lines = vim.api.nvim_buf_get_lines(view.buf, 0, 1, false)
	return lines[1] or ""
end

return M
