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

---@param on_change fun(text: string)
---@param total_w integer width for the input window
---@param total_h integer unused, kept for symmetry
---@param win_row integer top row of the picker layout
---@param win_col integer left col of the picker layout
---@param title? string title displayed in the input border
---@param debounce_ms? integer override debounce interval
---@param border? table border chars
---@return Beast.Finder.InputView
function M.create(on_change, total_w, total_h, win_row, win_col, title, debounce_ms, border)
	local buf = Buffer.new("beastvim-finder-input")
	vim.bo[buf].buftype = "prompt"
	vim.fn.prompt_setprompt(buf, config.prompt_prefix)

	local ns = vim.api.nvim_create_namespace("beastvim-finder-input")

	local display_title = " " .. (title or "Find") .. " "

	-- Input: top-left panel with full border. Right side junctions connect to preview.
	-- Bottom border ├─┤ is the visual separator between input and list.
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = total_w,
		height = 1,
		row = win_row,
		col = win_col,
		style = "minimal",
		border = border or { "╭", "─", "┬", "│", "┤", "─", "├", "│" },
		title = display_title,
		title_pos = "left",
		zindex = config.zindex,
	})

	Util.wo(win, "cursorline", false)
	Util.wo(win, "winhl", "Normal:BeastFinderInputNormal,FloatBorder:BeastFinderBorder,FloatTitle:BeastFinderInputTitle")

	local view = InputView(buf, win, ns)

	-- Highlight the prompt prefix
	local prefix_len = #config.prompt_prefix
	if prefix_len > 0 then
		vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
			end_col = prefix_len,
			hl_group = "BeastFinderInputPromptPrefix",
		})
	end

	local db_ms = debounce_ms or config.debounce.normal_ms
	vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
		buffer = buf,
		callback = function()
			-- stylua: ignore
			if view._timer then vim.fn.timer_stop(view._timer) end
			view._timer = vim.fn.timer_start(db_ms, function()
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
	local text = lines[1] or ""
	-- Strip the prompt prefix set by prompt_setprompt
	local prefix = config.prompt_prefix
	if prefix ~= "" and text:sub(1, #prefix) == prefix then
		text = text:sub(#prefix + 1)
	end
	return text
end

return M
