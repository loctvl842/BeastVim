local View = require("beast.libs.view")
local api = require("beast.libs.key.api")
local config = require("beast.libs.key.config")
local state = require("beast.libs.key.state")

---@class Beast.Key.UI.MainView : Beast.View
---@field ns integer
---@field backdrop Beast.View
local MainView = View:extend(function(obj, ns, backdrop)
	obj.ns = ns
	obj.backdrop = backdrop
end)

---@class Beast.Key.UI.ActionView : Beast.View
---@field ns integer
local ActionView = View:extend(function(obj, ns)
	obj.ns = ns
end)

local M = {}

-- =============================================================================
-- UTILS
-- =============================================================================

---@return integer width
---@return integer height
---@return integer row
---@return integer col
local function calc_main_geometry()
	local width = math.floor(vim.o.columns * config.ui.width)
	local height = math.floor(vim.o.lines * config.ui.height)
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)
	return width, height, row, col
end

---@param keys string|string[]
---@return string
local function keys_to_string(keys)
	if type(keys) == "table" then
		return table.concat(keys, ", ")
	end
	return keys
end

---@param actions Beast.Key.UI.Action[]
---@return integer
local function get_max_keys_width(actions)
	local max_width = 0
	for _, a in ipairs(actions) do
		local s = keys_to_string(a.keys)
		max_width = math.max(max_width, #s)
	end
	return max_width
end

---@param actions Beast.Key.UI.Action[]
---@return integer
local function calc_action_width(actions)
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
---@return integer width
---@return integer height
---@return integer row
---@return integer col
local function calc_action_geometry(main_win)
	local main_cfg = vim.api.nvim_win_get_config(main_win)
	local width = calc_action_width(config.ui.actions)
	local height = math.max(#config.ui.actions, 1)

	-- Top-right inside the main window with a little padding.
	local row = -1 -- offset into the winbar row
	local col = math.max((main_cfg.width or width) - width - 2, 0)

	return width, height, row, col
end

-- =============================================================================
-- MAIN VIEW
-- =============================================================================
local Main = {}

---@return Beast.Key.UI.MainView
function Main.create()
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

	View.win.wo(backdrop_win, "winblend", config.ui.backdrop)
	View.win.wo(backdrop_win, "winhighlight", "Normal:BeastKeyBackdrop")

	local width, height, row, col = calc_main_geometry()

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
	return MainView(main_buf, main_win, vim.api.nvim_create_namespace("beast_key_main"), View(backdrop_buf, backdrop_win))
end

---@param main Beast.Key.UI.MainView
function Main.layout(main)
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

	local width, height, row, col = calc_main_geometry()
	vim.api.nvim_win_set_config(main.win, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
	})
end

---@param main Beast.Key.UI.MainView
function Main.render(main)
  --stylua: ignore
  if not main:is_valid() then return end
	if not state.lines then
		state.lines = api.default()
	end
	local lines_segments = state.lines or {}

	local lines = {}
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
		lines[i] = s
	end
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	for _, m in ipairs(marks) do
		vim.api.nvim_buf_set_extmark(buf, ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
	end
end

---@param main Beast.Key.UI.MainView|nil
function Main.close(main)
  --stylua: ignore
  if not main then return end
	main.backdrop:close()
	main:close()
end

-- =============================================================================
-- ACTION VIEW
-- =============================================================================
local Action = {}

---@param main Beast.Key.UI.MainView
---@return Beast.Key.UI.ActionView
function Action.create(main)
	local buf = View.buf.new("beast-key-actions")
	local width, height, row, col = calc_action_geometry(main.win)

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
	return ActionView(buf, win, vim.api.nvim_create_namespace("beast_key_actions"))
end

---@param action Beast.Key.UI.ActionView
---@param main Beast.Key.UI.MainView
function Action.layout(action, main)
	if not action:is_valid() or not main:is_valid() then
		return
	end

	local width, height, row, col = calc_action_geometry(main.win)

	vim.api.nvim_win_set_config(action.win, {
		relative = "win",
		win = main.win,
		row = row,
		col = col,
		width = width,
		height = height,
	})
end

---@param action Beast.Key.UI.ActionView
function Action.render(action)
  --stylua: ignore
  if not action:is_valid() then return end

	vim.api.nvim_buf_clear_namespace(action.buf, action.ns, 0, -1)

	local max_keys_width = get_max_keys_width(config.ui.actions)

	for i, a in ipairs(config.ui.actions) do
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

		local padded_keys = string.format("%-" .. max_keys_width .. "s", keys)

		vim.api.nvim_buf_set_extmark(action.buf, action.ns, line0, 0, {
			virt_text = {
				{ " " .. padded_keys .. " ", a.key_hl or "ErrorMsg" },
				{ " " .. a.label, a.label_hl or "Comment" },
			},
			virt_text_pos = "overlay",
		})
	end
end

---@param action Beast.Key.UI.ActionView
function Action.close(action)
	action:close()
end

-- =============================================================================
-- ACTIONS
-- =============================================================================

local _actions_handler = {}

local actions = setmetatable({}, {
	__index = function(_, key)
		if _actions_handler[key] ~= nil then
			return _actions_handler[key]
		end
		error("Invalid action: " .. key)
	end,
})

function _actions_handler.close()
  --stylua: ignore
  if state.closed then return end

	if state.augroup ~= -1 then
		pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
	end

	Action.close(state.action)
	Main.close(state.main)

	state.reset()
end

function _actions_handler.cycle_mode()
	state.lines = api.cycle_mode()
	M.refresh()
end

function _actions_handler.toggle_beast()
	state.lines = api.toggle_beast_only()
	M.refresh()
end

function _actions_handler.expand_at_cursor()
	local line = vim.api.nvim_get_current_line()
	local id = line:match("%[.+%] (%S+)")
	if not id then
		return
	end
	state.lines = api.toggle_expand(id)
	M.refresh()
end

-- =============================================================================
-- Controller
-- =============================================================================
local function render_state()
	Main.render(state.main)
	Action.render(state.action)
end

local function layout_state()
	Main.layout(state.main)
	Action.layout(state.action, state.main)
end

local function mount_keymaps()
	for _, a in ipairs(config.ui.actions) do
		---@type string[]
		---@diagnostic disable-next-line: assign-type-mismatch
		local keys = type(a.keys) == "string" and { a.keys } or a.keys
		for _, key in ipairs(keys) do
			vim.keymap.set("n", key, actions[a.on_press], {
				buffer = state.main.buf,
				silent = true,
				nowait = true,
			})
		end
	end
end

local function mount_autocmds()
	state.augroup = vim.api.nvim_create_augroup("BeastKeyUI_" .. tostring(vim.loop.hrtime()), { clear = true })

	vim.api.nvim_create_autocmd("BufLeave", {
		group = state.augroup,
		buffer = state.main.buf,
		once = true,
		callback = function()
			actions.close()
		end,
	})

	vim.api.nvim_create_autocmd("WinEnter", {
		group = state.augroup,
		callback = function()
      -- stylua: ignore
			if state == nil or not state.is_valid() then return end
			local current = vim.api.nvim_get_current_win()
			if current ~= state.main.win then
				actions.close()
			end
		end,
	})

	vim.api.nvim_create_autocmd("VimResized", {
		group = state.augroup,
		callback = function()
      -- stylua: ignore
			if not state:is_valid() then return end
			layout_state()
		end,
	})
end

function M.open()
	if state.is_valid() then
		vim.api.nvim_set_current_win(state.main.win)
		return
	end
	local main = Main.create()
	local action = Action.create(main)
	state.main = main
	state.action = action
	mount_keymaps()
	mount_autocmds()
	render_state()
end

function M.refresh()
	if not state:is_valid() then
		return
	end
	render_state()
end

return M
