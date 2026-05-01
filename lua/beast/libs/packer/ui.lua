local View = require("beast.libs.view")
local config = require("beast.libs.packer.config")
local operation = require("beast.libs.packer.operation")
local profile = require("beast.libs.packer.profile")
local state = require("beast.libs.packer.state")

-- Spinner animation frames
local spinner_sets = {
	{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
	{ "·", "◦", "○", "◎", "⦿", "◎", "○", "◦" },
	{ "○", "◌", "◎", "◍", "●", "◍", "◎", "◌" },
	{ "🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘" },
}

-- seed once (important if you want different results each run)
math.randomseed(Util.hrtime())
local spinner_frames = spinner_sets[math.random(#spinner_sets)]
local spinner_index = 1

-- Refresh timer – drives spinner animation and live elapsed time during active operations
-- Declared here so stop_refresh_timer/start_refresh_timer (defined later) share the same upvalue
local refresh_timer = nil

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

	local row = -1 -- offset into the winbar row
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

	for _, segs in ipairs(segments) do
		local line_idx = #lines + 1
		lines[line_idx] = ""
		local col = 0
		for _, seg in ipairs(segs) do
			local parts = vim.split(seg.text, "\n", { plain = true })
			-- col at the start of this segment = indent for its continuation lines
			local seg_start_col = col
			for pi, part in ipairs(parts) do
				if pi > 1 then
					-- New buffer line; pad to align with where this segment started
					line_idx = #lines + 1
					local pad = string.rep(" ", seg_start_col)
					lines[line_idx] = pad
					col = seg_start_col
				end
				if seg.hl and #part > 0 then
					marks[#marks + 1] = { line_idx - 1, col, col + #part, seg.hl }
				end
				lines[line_idx] = lines[line_idx] .. part
				col = col + #part
			end
		end
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
	local backdrop_buf = Buffer.new("beast-backdrop")
	local main_buf = Buffer.new("beast-packer")
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
	Util.wo(backdrop_win, "winhighlight", "Normal:BeastPackerBackdrop")

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
	Util.wo(main_win, "colorcolumn", "")
	Util.wo(main_win, "winhighlight", "Normal:BeastPackerNormal,FloatBorder:BeastPackerBorder,WinBar:BeastPackerWinBar,WinBarNC:BeastPackerWinBar")

	return MainView(main_buf, main_win, vim.api.nvim_create_namespace("beast_packer_main"), View(backdrop_buf, backdrop_win))
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

	spinner_index = (spinner_index % #spinner_frames) + 1

	local winbar = "%#BeastPackerTitle#  🦁 Packer"
	if main.view_mode == "profile" then
		winbar = winbar .. "%#BeastPackerSubtitle# 󰿟 Profile"
	elseif main.view_mode == "help" then
		winbar = winbar .. "%#BeastPackerSubtitle# 󰿟 Help"
	end
	Util.wo(main.win, "winbar", winbar .. "%*")

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

---@param reason Beast.Packer.LoadReason|nil
---@return Beast.Packer.UI.Segment|nil
local function format_reason(reason)
	-- stylua: ignore
	if not reason then return nil end
	local t, d = reason.type, reason.detail
  local prefix = "  "
	if t == "eager" then
		return { text = prefix .. config.ui.icons.eager .. "Eager", hl = "BeastPackerTriggerEager" }
	elseif t == "dependency" then
		return { text = prefix .. config.ui.icons.dependencies .. "dep of " .. (d or "?"), hl = "BeastPackerComment" }
	elseif t == "event" then
		return { text = prefix .. config.ui.icons.event .. (d or "event"), hl = "BeastPackerTriggerEvent" }
	elseif t == "cmd" then
		return { text = prefix .. config.ui.icons.cmd .. ":" .. (d or "cmd"), hl = "BeastPackerTriggerCmd" }
	elseif t == "keys" then
		return { text = prefix .. config.ui.icons.keys .. (d or "keys"), hl = "BeastPackerTriggerKeys" }
	elseif t == "module" then
		return { text = prefix .. config.ui.icons.module .. "require('" .. (d or "?") .. "')", hl = "BeastPackerTriggerModule" }
	elseif t == "filetype" then
		return { text = prefix .. config.ui.icons.filetype .. (d or "filetype"), hl = "BeastPackerTriggerFiletype" }
	elseif t == "path" then
		return { text = prefix .. config.ui.icons.path .. (d or "path"), hl = "BeastPackerTriggerPath" }
	elseif t == "manual" then
		return { text = prefix .. "Manual", hl = "BeastPackerComment" }
	end
	return nil
end

---@param main Beast.Packer.UI.MainView
function Main._render_main(main)
  -- stylua: ignore
  if not main:is_valid() then return end

	---@type Beast.Packer.UI.Segment[][]
	local lines_segments = {}
	local new_line = { text = "", hl = nil }

	local total = state.total()
	local sort_text = main.sort_mode == "time" and "Time" or "Name"

	-- Collect install/update operations sorted by start_time (load ops shown in Loaded section)
	local ops_list = {}
	for name, op in pairs(operation.status) do
		if op.kind == "install" or op.kind == "update" then
			table.insert(ops_list, { name = name, op = op })
		end
	end
	table.sort(ops_list, function(a, b)
		return a.op.start_time < b.op.start_time
	end)

	if #ops_list > 0 then
		-- Batch progress subtitle
		local done_count = 0
		for _, item in ipairs(ops_list) do
			if item.op.status == "success" or item.op.status == "error" then
				done_count = done_count + 1
			end
		end
		table.insert(lines_segments, { { text = string.format("  Installing (%d/%d)   Sort: %s", done_count, #ops_list, sort_text), hl = "BeastPackerComment" } })
		table.insert(lines_segments, { new_line })

		-- Operations section
		table.insert(lines_segments, { { text = "  Operations ", hl = "BeastPackerH2" }, { text = "(" .. #ops_list .. ")", hl = "BeastPackerComment" } })
		for _, item in ipairs(ops_list) do
			local segments = {}
			local op = item.op
			if op.status == "in_progress" then
				local elapsed_ms = (Util.hrtime() - op.start_time_hr) / 1e6
				table.insert(segments, { text = "    " .. spinner_frames[spinner_index] .. " ", hl = "BeastPackerSpinner" })
				table.insert(segments, { text = item.name, hl = "BeastPackerPlugin" })
				table.insert(segments, { text = string.format("  %s  %.0fms", op.kind, elapsed_ms), hl = "BeastPackerComment" })
			elseif op.status == "success" then
				table.insert(segments, { text = "    " .. config.ui.icons.loaded .. " ", hl = "BeastPackerSuccess" })
				table.insert(segments, { text = item.name, hl = "BeastPackerPlugin" })
				table.insert(segments, { text = string.format("  %s  %.0fms", op.message or op.kind, op.elapsed_ms or 0), hl = "BeastPackerComment" })
			elseif op.status == "error" then
				table.insert(segments, { text = "    ✗ ", hl = "BeastPackerError" })
				table.insert(segments, { text = item.name, hl = "BeastPackerPlugin" })
				table.insert(segments, { text = "  " .. (op.message or "error"), hl = "BeastPackerError" })
			end
			table.insert(lines_segments, segments)
		end
		table.insert(lines_segments, { new_line })
	else
		table.insert(lines_segments, { { text = string.format("  Total: %d plugins   Sort: %s", total, sort_text), hl = "BeastPackerComment" } })
		table.insert(lines_segments, { new_line })
	end
	local loaded = {}
	local pending = {}
	for _, spec in pairs(state.plugins) do
		if state.loaded_plugins[spec.name] then
			table.insert(loaded, spec)
		elseif state.installed_plugins[spec.name] then
			table.insert(pending, spec)
		end
	end

	if main.sort_mode == "time" then
		table.sort(loaded, function(a, b)
			local pa = profile[a.name] or {} ---@type Beast.Packer.LoadProfile
			local pb = profile[b.name] or {} ---@type Beast.Packer.LoadProfile
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
		table.insert(lines_segments, { { text = "  Loaded ", hl = "BeastPackerH2" }, { text = "(" .. #loaded .. ")", hl = "BeastPackerComment" } })
		for _, spec in ipairs(loaded) do
			---@type Beast.Packer.UI.Segment[]
			local segments = {}
			table.insert(segments, { text = "    " .. config.ui.icons.loaded .. " ", hl = "BeastPackerProgress" })
			table.insert(segments, { text = spec.name, hl = "BeastPackerPlugin" })

			local prof = profile[spec.name]
			if prof and prof.total_ms and prof.total_ms > 0 then
				table.insert(segments, { text = string.format("  (%.1fms)", prof.total_ms), hl = "BeastPackerComment" })
			end

			local reason_seg = prof and format_reason(prof.reason)
			if reason_seg then
				table.insert(segments, new_line)
				table.insert(segments, reason_seg)
			end

			table.insert(lines_segments, segments)
		end
		table.insert(lines_segments, { new_line })
	end

	if #pending > 0 then
		-- Helper: normalize a trigger value to a list of strings
		local function to_list(v)
			if type(v) == "string" then
				return { v }
			end
			return v or {}
		end

		table.insert(lines_segments, { { text = "  Not Loaded ", hl = "BeastPackerH2" }, { text = "(" .. #pending .. ")", hl = "BeastPackerComment" } })
		for _, spec in ipairs(pending) do
			---@type Beast.Packer.UI.Segment[]
			local segments = {}
			table.insert(segments, { text = "    " .. config.ui.icons.pending .. " ", hl = "BeastPackerProgress" })
			table.insert(segments, { text = spec.name, hl = "BeastPackerPlugin" })

			if type(spec.lazy) == "table" then
				local lazy = spec.lazy
				for _, ev in ipairs(to_list(lazy.event)) do
					table.insert(segments, { text = "  " .. config.ui.icons.event .. ev, hl = "BeastPackerTriggerEvent" })
				end
				for _, cmd in ipairs(to_list(lazy.cmd)) do
					table.insert(segments, { text = "  " .. config.ui.icons.cmd .. cmd, hl = "BeastPackerTriggerCmd" })
				end
				for _, key in ipairs(to_list(lazy.keys)) do
					local lhs = type(key) == "string" and key or (type(key) == "table" and (key[1] or key.lhs) or "?")
					table.insert(segments, { text = "  " .. config.ui.icons.keys .. lhs, hl = "BeastPackerTriggerKeys" })
				end
				for _, mod in ipairs(to_list(lazy.module)) do
					table.insert(segments, { text = "  " .. config.ui.icons.module .. mod, hl = "BeastPackerTriggerModule" })
				end
				for _, ft in ipairs(to_list(lazy.filetype)) do
					table.insert(segments, { text = "  " .. config.ui.icons.filetype .. ft, hl = "BeastPackerTriggerFiletype" })
				end
				for _, p in ipairs(to_list(lazy.path)) do
					table.insert(segments, { text = "  " .. config.ui.icons.path .. p, hl = "BeastPackerTriggerPath" })
				end
			elseif spec.lazy == false then
				table.insert(segments, { text = "  " .. config.ui.icons.eager .. "Eager", hl = "BeastPackerTriggerEager" })
			else
				-- lazy == nil → manual
				table.insert(segments, { text = "  " .. config.ui.icons.lazy .. "Manual", hl = "BeastPackerComment" })
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

	table.insert(lines_segments, { new_line })

	local profiles = {}
	for name, prof in profile.iter() do
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

	apply_segments(main, lines_segments)
end

function Main._render_help(main)
  -- stylua: ignore
  if not main:is_valid() then return end

	---@type Beast.Packer.UI.Segment[][]
	local lines_segments = {}
	local new_line = { text = "", hl = nil }

	table.insert(lines_segments, { new_line })
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
	local buf = Buffer.new("beast-packer-actions")
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
	Util.wo(win, "winhighlight", "Normal:BeastPackerNormal")

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
local render_state = function()
	if state_data:is_valid() then
		Main.render(state_data.main)
		Action.render(state_data.action)
	end
end

local function stop_refresh_timer()
	-- stylua: ignore
	if not refresh_timer then return end
	refresh_timer:stop()
	refresh_timer:close()
	refresh_timer = nil
end

local function start_refresh_timer()
	-- stylua: ignore
	if refresh_timer then return end -- already running
	refresh_timer = (vim.uv or vim.loop).new_timer()
	---@diagnostic disable-next-line: need-check-nil
	refresh_timer:start(
		120,
		120,
		vim.schedule_wrap(function()
			if not state_data:is_valid() then
				stop_refresh_timer()
				return
			end
			render_state()
			vim.cmd("redraw")
			if not operation.any_in_progress() then
				stop_refresh_timer()
				render_state()
				vim.cmd("redraw")
			end
		end)
	)
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
		if operation.any_in_progress() then
			start_refresh_timer()
		end
		return
	end
	local main = Main.create()
	local action = Action.create(main)
	state_data.main = main
	state_data.action = action
	mount_keymaps()
	mount_autocmds()
	render_state()
	if operation.any_in_progress() then
		start_refresh_timer()
	end
	-- Neovim startup resets curwin to firstwin (create_windows + edit_buffers in main.c)
	-- after init.lua but before VimEnter. Re-assert focus at VimEnter.
	-- vim.schedule defers until after ALL VimEnter handlers finish (including lazy plugins
	-- triggered by VimEnter whose BufEnter/WinEnter can steal focus after our callback).
	if vim.v.vim_did_enter == 0 then
		vim.api.nvim_create_autocmd("VimEnter", {
			once = true,
			callback = function()
				vim.schedule(function()
					-- stylua: ignore
					if not state_data:is_valid() then return end
					vim.api.nvim_set_current_win(state_data.main.win)
					M.refresh()
				end)
			end,
		})
	end
end

function M.refresh()
	if not state_data:is_valid() then
		return
	end
	if operation.any_in_progress() then
		start_refresh_timer()
	end
	render_state()
end

function M.close()
  -- stylua: ignore
  if state_data.main == nil then return end
	stop_refresh_timer()
	operation.clear_completed()
	if state_data.augroup ~= -1 then
		pcall(vim.api.nvim_del_augroup_by_id, state_data.augroup)
	end

	Action.close(state_data.action)
	Main.close(state_data.main)

	state_data:reset()
end

function M.is_open()
	return state_data:is_valid()
end

return M
