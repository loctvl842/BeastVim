local View = require("beast.libs.view")
local config = require("beast.libs.key.config")

---@class Beast.Key.HintView : Beast.View
local HintView = View:extend()

local M = {}

local ns = vim.api.nvim_create_namespace("BeastKeyHint")

---@param items { key: string, child: Beast.Key.Hint.Node }[]
---@param title string
---@return integer width, integer height, string[] lines, integer max_key_w
local function measure(items, title)
	local max_key = 0
	for _, it in ipairs(items) do
		max_key = math.max(max_key, vim.fn.strdisplaywidth(it.key))
	end
	local lines = {}
	local max_line = vim.fn.strdisplaywidth(title)
	for _, it in ipairs(items) do
		local key = it.key
		local pad = string.rep(" ", max_key - vim.fn.strdisplaywidth(key))
		local desc
		if it.child.keymap and it.child.keymap.desc and it.child.keymap.desc ~= "" then
			desc = it.child.keymap.desc
		elseif it.child.group then
			desc = "+" .. it.child.group
		elseif next(it.child.children) then
			desc = "+prefix"
		else
			desc = ""
		end
		local line = string.format("%s%s  %s", pad, key, desc)
		table.insert(lines, line)
		max_line = math.max(max_line, vim.fn.strdisplaywidth(line))
	end
	if #lines == 0 then
		table.insert(lines, "(no mappings)")
		max_line = math.max(max_line, vim.fn.strdisplaywidth("(no mappings)"))
	end
	return max_line, #lines, lines, max_key
end

---@param state Beast.Key.Hint.State
---@param title string
---@param items { key: string, child: Beast.Key.Hint.Node }[]
function M.open_or_update(state, title, items)
	local win_cfg = config.hint.win
	local content_w, content_h, lines, max_key_w = measure(items, title)

	local pad_h, pad_w = win_cfg.padding[1], win_cfg.padding[2]
	local width = math.max(win_cfg.width.min, math.min(win_cfg.width.max, content_w + pad_w * 2))

	local max_h_setting = win_cfg.height.max
	local max_h
	if max_h_setting > 0 and max_h_setting <= 1 then
		max_h = math.floor(vim.o.lines * max_h_setting)
	else
		max_h = math.floor(max_h_setting)
	end
	local height = math.max(win_cfg.height.min, math.min(max_h, content_h + pad_h * 2))

	local padded_lines = {}
	for _ = 1, pad_h do
		table.insert(padded_lines, "")
	end
	for _, l in ipairs(lines) do
		table.insert(padded_lines, string.rep(" ", pad_w) .. l)
	end
	for _ = #padded_lines + 1, height do
		table.insert(padded_lines, "")
	end

	local buf
	if state.view and state.view:is_valid() then
		buf = state.view.buf
		vim.bo[buf].modifiable = true
	else
		buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].buftype = "nofile"
		vim.bo[buf].bufhidden = "wipe"
		vim.bo[buf].swapfile = false
		vim.bo[buf].filetype = "beast-key-hint"
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, padded_lines)
	vim.bo[buf].modifiable = false

	-- Highlights
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	for i, it in ipairs(items) do
		local row = i - 1 + pad_h
		local prefix_w = pad_w + (max_key_w - vim.fn.strdisplaywidth(it.key))
		local key_end = prefix_w + #it.key
		vim.api.nvim_buf_add_highlight(buf, ns, "BeastKeyHintKey", row, prefix_w, key_end)
		local desc_start = key_end + 2 -- two spaces separator
		local is_group = it.child.group ~= nil and not it.child.keymap
		local hl = is_group and "BeastKeyHintGroup" or "BeastKeyHintDesc"
		vim.api.nvim_buf_add_highlight(buf, ns, hl, row, desc_start, -1)
	end

	local win
	if state.view and state.view:is_valid() then
		win = state.view.win
		vim.api.nvim_win_set_config(win, {
			relative = "editor",
			anchor = win_cfg.anchor,
			row = vim.o.lines - 2, -- above the cmdline
			col = vim.o.columns - 1,
			width = width,
			height = height,
			title = title,
			title_pos = win_cfg.title_pos,
		})
	else
		win = vim.api.nvim_open_win(buf, false, {
			relative = "editor",
			anchor = win_cfg.anchor,
			row = vim.o.lines - 2,
			col = vim.o.columns - 1,
			width = width,
			height = height,
			focusable = false,
			noautocmd = true,
			style = "minimal",
			border = win_cfg.border,
			title = title,
			title_pos = win_cfg.title_pos,
			zindex = 200,
		})
		state.view = HintView:new(buf, win)
	end

	-- Window-local options
	vim.wo[win].winhighlight = table.concat({
		"Normal:BeastKeyHintNormal",
		"FloatBorder:BeastKeyHintBorder",
		"FloatTitle:BeastKeyHintTitle",
	}, ",")
	vim.wo[win].wrap = false
	vim.wo[win].cursorline = false
end

---@param state Beast.Key.Hint.State
function M.close(state)
	if state.delay_timer then
		state.delay_timer:stop()
		state.delay_timer:close()
		state.delay_timer = nil
	end
	state.done = true
	if state.view then
		state.view:close()
		state.view = nil
	end
end

return M
