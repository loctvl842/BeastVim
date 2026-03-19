local View = require("beast.libs.view")

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

---@class Beast.Key.UI.State
---@field main Beast.Key.UI.MainView
---@field action Beast.Key.UI.ActionView
---@field augroup integer
---@field closed boolean
local State = {}
State.__index = State

function State:new(main, action, augroup)
	return setmetatable({
		main = main,
		action = action,
		augroup = augroup,
		closed = false,
	}, self)
end

function State:is_valid()
	return not self.closed and self.main:is_valid() and self.action:is_valid()
end

---@class Beast.Key.UI.Action
---@field keys string[]|string
---@field label string
---@field key_hl string
---@field label_hl string
---@field on_press function

---@class Beast.Key.UI.Hooks
---@field main? Beast.Key.UI.MainHooks
---@field action? Beast.Key.UI.ActionHooks

---@class Beast.Key.UI.MainHooks
---@field render? fun(main: Beast.Key.UI.MainView, state: Beast.Key.UI.State)

---@class Beast.Key.UI.ActionHooks
---@field render? fun(action: Beast.Key.UI.Action, state: Beast.Key.UI.State)

local M = {}

---@type Beast.Key.UI.State|nil
local state

---@class Beast.Key.UI.Config
local defaults = {
	width = 0.7,
	height = 0.7,
	backdrop = 30,
	---@type Beast.Key.UI.Action[]
	actions = {
		{
			keys = { "q", "<Esc>" },
			label = "Close",
			key_hl = "DiagnosticError",
			label_hl = "Comment",
			on_press = function()
				M.close()
			end,
		},
	},
	---@type Beast.Key.UI.Hooks
	hooks = {},
}

---@type Beast.Key.UI.Config
local cfg = vim.deepcopy(defaults)

-- =============================================================================
-- UTILS
-- =============================================================================

---@param filetype string
---@return integer
local function create_scratch_buf(filetype)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = filetype
	return buf
end

---@return integer width
---@return integer height
---@return integer row
---@return integer col
local function calc_main_geometry()
	local width = math.floor(vim.o.columns * cfg.width)
	local height = math.floor(vim.o.lines * cfg.height)
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
	local max_len = 0
	for _, a in ipairs(actions) do
		local keys = keys_to_string(a.keys)
		local text = string.format("%s %s", keys, a.label)
		max_len = math.max(max_len, vim.fn.strdisplaywidth(text))
	end
	return math.max(max_len, 1) + 2
end

---@param main_win integer
---@return integer width
---@return integer height
---@return integer row
---@return integer col
local function calc_action_geometry(main_win)
	local main_cfg = vim.api.nvim_win_get_config(main_win)
	local width = calc_action_width(cfg.actions)
	local height = math.max(#cfg.actions, 1)

	-- Top-right inside the main window with a little padding.
	local row = 0
	local col = math.max((main_cfg.width or width) - width - 2, 0)

	return width, height, row, col
end

-- =============================================================================
-- MAIN VIEW
-- =============================================================================
local Main = {}

---@return Beast.Key.UI.MainView
function Main.create()
	local backdrop_buf = create_scratch_buf("beast-backdrop")
	local main_buf = create_scratch_buf("beast-key")
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

	Util.wo(backdrop_win, "winblend", cfg.backdrop)

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

	Util.wo(main_win, "wrap", false)
	Util.wo(main_win, "number", false)
	Util.wo(main_win, "relativenumber", false)
	Util.wo(main_win, "signcolumn", "no")
	return MainView(
		main_buf,
		main_win,
		vim.api.nvim_create_namespace("beast_key_main"),
		View(backdrop_buf, backdrop_win)
	)
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

	local lines = {
		"Beast Key UI",
		"",
		"Please implement me!",
	}

	vim.bo[main.buf].modifiable = true
	vim.api.nvim_buf_set_lines(main.buf, 0, -1, false, lines)
	vim.bo[main.buf].modifiable = false
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
	local buf = create_scratch_buf("beast-key-actions")
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

	Util.wo(win, "winblend", 0)
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

	local max_keys_width = get_max_keys_width(cfg.actions)

	for i, a in ipairs(cfg.actions) do
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
-- Controller
-- =============================================================================
---@param component "main"|"action"
---@param name "render"
---@return function
local function get_hook(component, name)
	local hook = cfg.hooks and cfg.hooks[component] and cfg.hooks[component][name]

	if hook then
		return hook
	end

	if component == "main" then
		if name == "render" then
			return Main.render
		end
		assert(name == "layout", "Invalid hook name: " .. name)
	end

	if component == "action" then
		if name == "render" then
			return Action.render
		end
		assert(name == "layout", "Invalid hook name: " .. name)
	end

	error("Invalid hook name: " .. name)
end

---@return Beast.Key.UI.State
local function create_state()
	local main = Main.create()
	local action = Action.create(main)
	return State:new(main, action, -1)
end

---@param s Beast.Key.UI.State
local function render_state(s)
	get_hook("main", "render")(s.main)
	get_hook("action", "render")(s.action)
end

---@param s Beast.Key.UI.State
local function layout_state(s)
	Main.layout(s.main)
	Action.layout(s.action, s.main)
end

---@param s Beast.Key.UI.State
local function mount_keymaps(s)
	for _, a in ipairs(cfg.actions) do
		---@type string[]
		---@diagnostic disable-next-line: assign-type-mismatch
		local keys = type(a.keys) == "string" and { a.keys } or a.keys
		for _, key in ipairs(keys) do
			vim.keymap.set("n", key, function()
				a.on_press(s.main)
			end, {
				buffer = s.main.buf,
				silent = true,
				nowait = true,
			})
		end
	end
end

---@param s Beast.Key.UI.State
local function mount_autocmds(s)
	s.augroup = vim.api.nvim_create_augroup("BeastKeyUI_" .. tostring(vim.loop.hrtime()), { clear = true })

	vim.api.nvim_create_autocmd("BufLeave", {
		group = s.augroup,
		buffer = s.main.buf,
		once = true,
		callback = function()
			M.close()
		end,
	})

	vim.api.nvim_create_autocmd("WinEnter", {
		group = s.augroup,
		callback = function()
      -- stylua: ignore
			if state == nil or not state:is_valid() then return end
			local current = vim.api.nvim_get_current_win()
			if state ~= nil and current ~= state.main.win then
				M.close()
			end
		end,
	})

	vim.api.nvim_create_autocmd("VimResized", {
		group = s.augroup,
		callback = function()
      -- stylua: ignore
			if state == nil or not state:is_valid() then return end
			layout_state(state)
		end,
	})
end

function M.open()
	if state ~= nil and state:is_valid() then
		vim.api.nvim_set_current_win(state.main.win)
		return state
	end
	state = create_state()
	mount_keymaps(state)
	mount_autocmds(state)
	render_state(state)

	return state
end

function M.close()
  --stylua: ignore
  if not state or state.closed then return end

	state.closed = true
	if state.augroup and state.augroup ~= -1 then
		pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
	end

	Action.close(state.action)
	Main.close(state.main)

	state = nil
end

---@param opts? Beast.Key.UI.Config
function M.setup(opts)
	cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

return M
