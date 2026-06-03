local View = require("beast.libs.view")
local config = require("beast.libs.finder.config")

local spinner_sets = {
	{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
	{ "·", "◦", "○", "◎", "⦿", "◎", "○", "◦" },
	{ "○", "◌", "◎", "◍", "●", "◍", "◎", "◌" },
	{ "🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘" },
}
local SPINNER_INTERVAL_MS = 80

---@class Beast.Finder.InputView : Beast.View
---@field ns integer
---@field _debounced Beast.Util.Debouncer|nil
---@field _spinner_timer uv.uv_timer_t|nil
---@field _spinner_frame integer
---@field _spinner_extmark integer|nil
local InputView = View:extend(function(obj, ns)
	obj.ns = ns
	obj._debounced = nil
	obj._spinner_timer = nil
	obj._spinner_frame = 0
	obj._spinner_extmark = nil
end)

---@class Beast.Finder.UI.Input
local M = {}

---@param on_change fun(text: string)
---@param total_w integer width for the input window
---@param total_h integer height for the input window
---@param win_row integer top row of the picker layout
---@param win_col integer left col of the picker layout
---@param title? string title displayed in the input border
---@param debounce_ms? integer override debounce interval
---@param border? table border chars
function M.create(on_change, total_w, total_h, win_row, win_col, title, debounce_ms, border)
	local buf = View.buf.new("beast-finder-input")
	vim.bo[buf].buftype = "prompt"

	local ns = vim.api.nvim_create_namespace("beast-finder-input")

	local display_title = " " .. (title or "Find") .. " "

	-- Input: top-left panel with full border. Right side junctions connect to preview.
	-- Bottom border ├─┤ is the visual separator between input and list.
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = total_w,
		height = total_h,
		row = win_row,
		col = win_col,
		style = "minimal",
		border = border or { "╭", "─", "┬", "│", "┤", "─", "├", "│" },
		title = display_title,
		title_pos = "left",
		zindex = 103,
	})

	View.win.wo(win, "cursorline", false)
	View.win.wo(win, "winhl", "Normal:BeastFinderInputNormal,FloatBorder:BeastFinderBorder,FloatTitle:BeastFinderInputTitle")

	local view = InputView(buf, win, ns)

	-- Set prompt prefix so the buffer line contains the prefix text
	local prefix = config.prompt_prefix
	if prefix ~= "" then
		vim.fn.prompt_setprompt(buf, prefix)
	end

	-- Highlight the prompt prefix (safe now that the line has content)
	local prefix_len = #prefix
	if prefix_len > 0 then
		vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
			end_col = prefix_len,
			hl_group = "BeastFinderInputPromptPrefix",
		})
	end

	local db_ms = debounce_ms or config.debounce.normal_ms
	view._debounced = Util.debounce(db_ms, function()
		-- stylua: ignore
		if not view:is_valid() then return end
		local text = M.get_text(view)
		on_change(text)
	end)
	vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
		buffer = buf,
		callback = function()
			if view._debounced then
				view._debounced()
			end
		end,
	})

	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = buf,
		once = true,
		callback = function()
			if view._debounced then
				view._debounced:close()
				view._debounced = nil
			end

			M.stop_spinner(view)
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

--- Show a spinning indicator right-aligned in the input window
---@param view Beast.Finder.InputView
function M.start_spinner(view)
	-- stylua: ignore
	if view._spinner_timer and not view._spinner_timer:is_closing() then return end

	local frames = spinner_sets[math.random(#spinner_sets)]
	view._spinner_frame = 0
	view._spinner_timer = assert(vim.uv.new_timer(), "failed to create spinner timer")

	local function tick()
		-- stylua: ignore
		if not view:is_valid() then return end
		view._spinner_frame = (view._spinner_frame % #frames) + 1
		local frame = frames[view._spinner_frame]

		-- Clear previous extmark
		if view._spinner_extmark then
			pcall(vim.api.nvim_buf_del_extmark, view.buf, view.ns, view._spinner_extmark)
		end
		view._spinner_extmark = vim.api.nvim_buf_set_extmark(view.buf, view.ns, 0, 0, {
			virt_text = { { frame, "BeastFinderSpinner" } },
			virt_text_pos = "right_align",
		})
		vim.cmd("redraw")
	end

	tick()
	view._spinner_timer:start(SPINNER_INTERVAL_MS, SPINNER_INTERVAL_MS, vim.schedule_wrap(tick))
end

--- Stop the spinning indicator
---@param view Beast.Finder.InputView
function M.stop_spinner(view)
	if view._spinner_timer and not view._spinner_timer:is_closing() then
		view._spinner_timer:stop()
		view._spinner_timer:close()
	end
	view._spinner_timer = nil

	if view._spinner_extmark and view:is_valid() then
		pcall(vim.api.nvim_buf_del_extmark, view.buf, view.ns, view._spinner_extmark)
		view._spinner_extmark = nil
	end
end

return M
