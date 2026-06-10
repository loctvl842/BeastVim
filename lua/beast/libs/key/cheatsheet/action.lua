local View = require("beast.libs.view")
local config = require("beast.libs.key.config")

---@class Beast.Key.Cheatsheet.ActionView : Beast.View.Instance
---@field ns integer
---@overload fun(buf?: integer, win?: integer, ns: integer): Beast.Key.Cheatsheet.ActionView
local ActionView = View:extend(
	---@param obj Beast.Key.Cheatsheet.ActionView
	function(obj, ns)
		obj.ns = ns
	end
)

local M = {}

---@param keys string|string[]
---@return string
local function keys_to_string(keys)
	if type(keys) == "table" then
		return table.concat(keys, ", ")
	end
	return keys
end

---@param actions Beast.Key.Cheatsheet.Action[]
---@return integer
local function max_keys_width(actions)
	local m = 0
	for _, a in ipairs(actions) do
		m = math.max(m, #keys_to_string(a.keys))
	end
	return m
end

---@param actions Beast.Key.Cheatsheet.Action[]
---@return integer
local function calc_width(actions)
	local max_len_key = 0
	local max_len_label = 0
	for _, a in ipairs(actions) do
		local keys = keys_to_string(a.keys)
		max_len_key = math.max(max_len_key, vim.fn.strdisplaywidth(keys))
		max_len_label = math.max(max_len_label, vim.fn.strdisplaywidth(a.label))
	end
	return math.max(max_len_key + max_len_label + 1, 2) + 2
end

---@param main_win integer
---@return integer width, integer height, integer row, integer col
local function calc_geometry(main_win)
	local main_cfg = vim.api.nvim_win_get_config(main_win)
	local width = calc_width(config.cheatsheet.actions)
	local height = math.max(#config.cheatsheet.actions, 1)
	local row = -1 -- offset into the winbar row
	local col = math.max((main_cfg.width or width) - width - 2, 0)
	return width, height, row, col
end

---@param main Beast.Key.Cheatsheet.MainView
---@return Beast.Key.Cheatsheet.ActionView
function M.create(main)
	local buf = View.buf.new("beast-key-actions")
	local width, height, row, col = calc_geometry(main.win)

	local win = vim.api.nvim_open_win(buf, false, {
		relative = "win",
		win = main.win,
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "none",
		focusable = false,
		zindex = 102,
		noautocmd = true,
	})

	View.win.wo(win, "winblend", 0)
	View.win.wo(win, "winhighlight", "Normal:BeastPackerNormal")
	return ActionView(buf, win, vim.api.nvim_create_namespace("beast_key_cheatsheet_actions"))
end

---@param action Beast.Key.Cheatsheet.ActionView
---@param main Beast.Key.Cheatsheet.MainView
function M.layout(action, main)
	if not action:is_valid() or not main:is_valid() then
		return
	end

	local width, height, row, col = calc_geometry(main.win)

	vim.api.nvim_win_set_config(action.win, {
		relative = "win",
		win = main.win,
		row = row,
		col = col,
		width = width,
		height = height,
	})
end

---@param action Beast.Key.Cheatsheet.ActionView
function M.render(action)
  --stylua: ignore
  if not action:is_valid() then return end

	vim.api.nvim_buf_clear_namespace(action.buf, action.ns, 0, -1)

	local keys_w = max_keys_width(config.cheatsheet.actions)

	for i, a in ipairs(config.cheatsheet.actions) do
		local line0 = i - 1
		local line_count = vim.api.nvim_buf_line_count(action.buf)

		-- Ensure anchor line exists
		if line0 >= line_count then
			vim.bo[action.buf].modifiable = true
			for _ = line_count, line0 do
				vim.api.nvim_buf_set_lines(action.buf, -1, -1, false, { "" })
			end
			vim.bo[action.buf].modifiable = false
		end

		local keys = keys_to_string(a.keys)
		local padded_keys = string.format("%-" .. keys_w .. "s", keys)

		vim.api.nvim_buf_set_extmark(action.buf, action.ns, line0, 0, {
			virt_text = {
				{ " " .. padded_keys .. " ", a.key_hl or "ErrorMsg" },
				{ " " .. a.label, a.label_hl or "Comment" },
			},
			virt_text_pos = "overlay",
		})
	end
end

---@param action Beast.Key.Cheatsheet.ActionView
function M.close(action)
	action:close()
end

return M
