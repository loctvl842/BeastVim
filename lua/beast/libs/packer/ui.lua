local View = require("beast.libs.view")
local config = require("beast.libs.packer.config")
local state = require("beast.libs.packer.state")

-- Spinner animation frames
local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local spinner_index = 1

---@class Beast.Packer.UI.MainView : Beast.View
---@field ns integer Namespace for extmarks
---@field backdrop Beast.View Backdrop window for dimming background
---@field sort_mode? "name"|"time"
---@field view_mode? "main"|"profile"|"help"
local MainView = View:extend(function(obj, ns, backdrop, sort_mode, view_mode)
	obj.ns = ns
	obj.backdrop = backdrop
	obj.sort_mode = sort_mode or "name"
	obj.view_mode = view_mode or "main"
end)

---@class Beast.Packer.UI.ActionView : Beast.View
---@field ns integer
local ActionView = View:extend(function(obj, ns)
	obj.ns = ns
end)

local M = {}

-- =============================================================================
-- UI STATE
-- =============================================================================
local state_data = {
	---@type Beast.Packer.UI.MainView
	main = nil,
	---@type Beast.Packer.UI.ActionView
	action = nil,
	---@type integer
	augroup = -1,
}

function state_data:is_valid()
	return self.main ~= nil and self.main:is_valid() and self.action ~= nil and self.action:is_valid()
end

function state_data:reset()
	self.main = nil
	self.action = nil
	self.augroup = -1
end

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

---@param actions Beast.Packer.UI.Action[]
---@return integer
local function get_max_keys_width(actions)
	local max_width = 0
	for _, a in ipairs(actions) do
		local s = keys_to_string(a.keys)
		max_width = math.max(max_width, #s)
	end
	return max_width
end

---@param actions Beast.Packer.UI.Action[]
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
---@return integer width, integer height, integer row, integer col
local function calc_action_geometry(main_win)
	local main_cfg = vim.api.nvim_win_get_config(main_win)
	local width = calc_action_width(config.ui.actions)
	local height = math.max(#config.ui.actions, 1)

	local row = 0
	local col = math.max((main_cfg.width or width) - width - 2, 0)

	return width, height, row, col
end

---@class Beast.Packer.UI.Segment
---@field text string
---@field hl? string

---@param main Beast.Packer.UI.MainView
---@param segments Beast.Packer.UI.Segment[][]
local function apply_segments(main, segments)
	local lines = {}
	local marks = {}
	local ns = main.ns
	local buf = main.buf

	for i, segs in ipairs(segments) do
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

-- =============================================================================
-- MAIN VIEW
-- =============================================================================
local Main = {}

function Main.create()
	local backdrop_buf = Util.create_scratch_buf("beast-backdrop")
	local main_buf = Util.create_scratch_buf("beastpacker")
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

	Util.wo(backdrop_win, "winblend", config.ui.backdrop)

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
	Util.wo(main_win, "conceallevel", 3)
	Util.wo(main_win, "concealcursor", "nvic")
	Util.wo(main_win, "cursorline", false)

	return MainView(
		main_buf,
		main_win,
		vim.api.nvim_create_namespace("beast_packer_main"),
		View(backdrop_buf, backdrop_win)
	)
end

---@param main Beast.Packer.UI.MainView
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

---@param main Beast.Packer.UI.MainView
function Main.render(main)
  -- stylua: ignore
  if not main:is_valid() then return end

  -- TODO: implement spinner
	spinner_index = (spinner_index % #spinner_frames) + 1

	if main.view_mode == "main" then
		Main._render_main(main)
	elseif main.view_mode == "profile" then
		Main._render_profile(main)
	elseif main.view_mode == "help" then
		Main._render_help(main)
	else
		error("Invalid view mode: " .. main.view_mode)
	end
end

---@param main Beast.Packer.UI.MainView
function Main._render_main(main)
  -- stylua: ignore
  if not main:is_valid() then return end

	---@type Beast.Packer.UI.Segment[][]
	local lines_segments = {}
	local title = "  🦁 Packer"
	local new_line = { text = "", hl = nil }
	table.insert(lines_segments, { { text = title, hl = "BeastPackerH2" } })

	local total = #state.lazy_plugins
	local loaded_count = 0
	for _, spec in ipairs(state.lazy_plugins) do
		if state.load_profiles[spec.name] then
			loaded_count = loaded_count + 1
		end
	end
	local sort_text = main.sort_mode == "time" and "Time" or "Name"
	table.insert(
		lines_segments,
		{ { text = string.format("  Total: %d plugins   Sort: %s", total, sort_text) }, hl = "BeastPackerComment" }
	)
	table.insert(lines_segments, { new_line })
	local loaded = {}
	local pending = {}
	for _, spec in ipairs(state.lazy_plugins) do
		if state.loaded_plugins[spec.name] then
			table.insert(loaded, spec)
		else
			table.insert(pending, spec)
		end
	end

	if main.sort_mode == "time" then
		table.sort(loaded, function(a, b)
			local pa = state.load_profiles[a.name] or {}
			local pb = state.load_profiles[b.name] or {}
			local ta = pa.total_ms or 0
			local tb = pb.total_ms or 0
			if ta == tb then
				return a.name < b.name
			end
			return ta > tb
		end)
	else
		table.sort(loaded, function(a, b)
			return a.name < b.name
		end)
	end

	if #loaded > 0 then
		table.insert(lines_segments, { { text = "  Loaded (" .. #loaded .. ")", hl = "BeastPackerH2" } })
		for _, spec in ipairs(loaded) do
			---@type Beast.Packer.UI.Segment[]
			local segments = {}
			table.insert(segments, { text = "  " .. config.ui.icons.loaded .. " ", hl = "BeastPackerSpecial" })
			table.insert(segments, { text = spec.name, hl = "BeastPackerPlugin" })

			local prof = state.load_profiles[spec.name]
			if prof and prof.total_ms and prof.total_ms > 0 then
				table.insert(segments, { text = string.format("  (%.1fms)", prof.total_ms), hl = "BeastPackerComment" })
			end

			table.insert(lines_segments, segments)
		end
		table.insert(lines_segments, { new_line })
	end

	if #pending > 0 then
		table.insert(lines_segments, { { text = "  Not Loaded (" .. #pending .. ")", hl = "BeastPackerH2" } })
		for _, spec in ipairs(pending) do
			---@type Beast.Packer.UI.Segment[]
			local segments = {}
			table.insert(segments, { text = "  " .. config.ui.icons.pending .. " ", hl = "BeastPackerComment" })
			table.insert(segments, { text = spec.name, hl = "BeastPackerPlugin" })

			if type(spec.lazy) == "table" then
				if spec.lazy.event then
					local events = type(spec.lazy.event) == "string" and { spec.lazy.event } or spec.lazy.event
					table.insert(
						segments,
						{ text = "  " .. config.ui.icons.event .. " " .. events[1], hl = "BeastPackerEvent" }
					)
				elseif spec.lazy.cmd then
					local cmds = type(spec.lazy.cmd) == "string" and { spec.lazy.cmd } or spec.lazy.cmd
					table.insert(
						segments,
						{ text = "  " .. config.ui.icons.cmd .. " :" .. cmds[1], hl = "BeastPackerCmd" }
					)
				end
			end
			table.insert(lines_segments, segments)
		end
		table.insert(lines_segments, { new_line })
	end
	apply_segments(main, lines_segments)
end

function Main._render_profile(main)
  -- stylua: ignore
  if not main:is_valid() then return end

	---@type Beast.Packer.UI.Segment[][]
	local lines_segments = {}
	---@type Beast.Packer.UI.Segment
	local new_line = { text = "", hl = nil }

	table.insert(lines_segments, { { text = "  Load Profile (sorted by time)", hl = "BeastPackerH2" } })

	local profiles = {}
	for name, prof in pairs(state.load_profiles) do
		if prof.total_ms and prof.total_ms > 0 then
			table.insert(profiles, { name = name, prof = prof })
		end
	end

	table.sort(profiles, function(a, b)
		return (a.prof.total_ms or 0) > (b.prof.total_ms or 0)
	end)

	for _, item in ipairs(profiles) do
		local segments = {}
		table.insert(segments, { text = "  ", hl = nil })
		table.insert(segments, { text = item.name, hl = "BeastPackerPlugin" })
		table.insert(segments, { text = string.format("  %.1fms", item.prof.total_ms), hl = "BeastPackerComment" })
		table.insert(lines_segments, segments)
	end

	table.insert(lines_segments, { new_line })
	apply_segments(main, lines_segments)
end

function Main._render_help(main)
  -- stylua: ignore
  if not main:is_valid() then return end

	---@type Beast.Packer.UI.Segment[][]
	local lines_segments = {}

	table.insert(lines_segments, { { text = "  Packer Help", hl = "BeastPackerH2" } })
	table.insert(lines_segments, { { text = "", hl = nil } })
	table.insert(lines_segments, { { text = "  S - Toggle sort (name/time)", hl = "BeastPackerComment" } })
	table.insert(lines_segments, { { text = "  P - Show profile", hl = "BeastPackerComment" } })
	table.insert(lines_segments, { { text = "  ? - Show help", hl = "BeastPackerComment" } })
	table.insert(lines_segments, { { text = "  Q - Close", hl = "BeastPackerComment" } })

	apply_segments(main, lines_segments)
end

---@param main Beast.Packer.UI.MainView
function Main.close(main)
  -- stylua: ignore
  if not main then return end

	main.backdrop:close()
	main:close()
end

-- =============================================================================
-- ACTION VIEW
-- =============================================================================

local Action = {}

---@param main Beast.Packer.UI.MainView
---@return Beast.Packer.UI.ActionView
function Action.create(main)
	local buf = Util.create_scratch_buf("beast-packer-actions")
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

	return ActionView(buf, win, vim.api.nvim_create_namespace("beast_packer_actions"))
end

---@param action Beast.Packer.UI.ActionView
---@param main Beast.Packer.UI.MainView
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

---@param action Beast.Packer.UI.ActionView
function Action.render(action)
  -- stylua: ignore
  if not action:is_valid() then return end

	vim.api.nvim_buf_clear_namespace(action.buf, action.ns, 0, -1)

	local max_keys_width = get_max_keys_width(config.ui.actions)
	for i, a in ipairs(config.ui.actions) do
		local line0 = i - 1
		local line_count = vim.api.nvim_buf_line_count(action.buf)

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

---@param action Beast.Packer.UI.ActionView
function Action.close(action)
	action:close()
end

-- =============================================================================
-- Controller
-- =============================================================================
local function render_state()
	if state_data:is_valid() then
		Main.render(state_data.main)
		Action.render(state_data.action)
	end
end

local function layout_state()
	if state_data:is_valid() then
		Main.layout(state_data.main)
		Action.layout(state_data.action, state_data.main)
	end
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

function _actions_handler.sort()
	if state_data:is_valid() then
		state_data.main.sort_mode = state_data.main.sort_mode == "name" and "time" or "name"
		render_state()
	end
end

function _actions_handler.view_profile()
	if state_data:is_valid() then
		state_data.main.view_mode = state_data.main.view_mode == "profile" and "main" or "profile"
		render_state()
	end
end

function _actions_handler.view_help()
	if state_data:is_valid() then
		state_data.main.view_mode = state_data.main.view_mode == "help" and "main" or "help"
		render_state()
	end
end

function _actions_handler.close()
	M.close()
end

local function mount_keymaps()
	for _, a in ipairs(config.ui.actions) do
		---@type string[]
		---@diagnostic disable-next-line: assign-type-mismatch
		local keys = type(a.keys) == "string" and { a.keys } or a.keys
		for _, key in ipairs(keys) do
			vim.keymap.set("n", key, actions[a.on_press], {
				buffer = state_data.main.buf,
				silent = true,
				nowait = true,
			})
		end
	end
end

local function mount_autocmds()
	state_data.augroup = vim.api.nvim_create_augroup("BeastPackerUI_" .. tostring(vim.loop.hrtime()), { clear = true })

	vim.api.nvim_create_autocmd("BufLeave", {
		group = state_data.augroup,
		buffer = state_data.main.buf,
		callback = function()
			M.close()
		end,
	})

	vim.api.nvim_create_autocmd("WinEnter", {
		group = state_data.augroup,
		callback = function()
      -- stylua: ignore
      if state_data == nil or not state_data:is_valid() then return end
			local current = vim.api.nvim_get_current_win()
			if current ~= state_data.main.win then
				M.close()
			end
		end,
	})

	vim.api.nvim_create_autocmd("VimResized", {
		group = state_data.augroup,
		callback = function()
      -- stylua: ignore
      if not state_data:is_valid() then return end
			layout_state()
		end,
	})
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================
function M.open()
	if state_data:is_valid() then
		render_state()
		vim.api.nvim_set_current_win(state_data.main.win)
		return
	end
	local main = Main.create()
	local action = Action.create(main)
	state_data.main = main
	state_data.action = action
	mount_keymaps()
	mount_autocmds()
	render_state()
	-- Neovim startup resets curwin to firstwin (create_windows + edit_buffers in main.c)
	-- after init.lua but before VimEnter. Re-assert focus at VimEnter.
	if vim.v.vim_did_enter == 0 then
		vim.api.nvim_create_autocmd("VimEnter", {
			once = true,
			callback = function()
				-- stylua: ignore
				if not state_data:is_valid() then return end
				vim.api.nvim_set_current_win(state_data.main.win)
			end,
		})
	end
end

function M.refresh()
	if not state_data:is_valid() then
		return
	end
	render_state()
end

function M.close()
  -- stylua: ignore
  if state_data.main == nil then return end
	if state_data.augroup ~= -1 then
		pcall(vim.api.nvim_del_augroup_by_id, state_data.augroup)
	end

	Action.close(state_data.action)
	Main.close(state_data.main)

	state_data:reset()
end

return M
