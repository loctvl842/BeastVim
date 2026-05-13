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
---@field profile_sort? "total"|"packadd"|"config"|"name"|"chrono"
---@field profile_filter_ms? number
---@field profile_group_by_reason? boolean
local MainView = View:extend(function(obj, ns, backdrop, sort_mode, view_mode)
	obj.ns = ns
	obj.backdrop = backdrop
	obj.sort_mode = sort_mode or "name"
	obj.view_mode = view_mode or "main"
	obj.profile_sort = "total"
	obj.profile_filter_ms = 0
	obj.profile_group_by_reason = false
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

---@param view_mode string
---@return Beast.Packer.UI.Action[]
local function actions_for_view(view_mode)
	local result = {}
	for _, a in ipairs(config.ui.actions) do
		if a.views then
			for _, v in ipairs(a.views) do
				if v == view_mode then
					table.insert(result, a)
					break
				end
			end
		else
			table.insert(result, a)
		end
	end
	return result
end

---@param main_win integer
---@param view_mode string
---@return integer width, integer height, integer row, integer col
local function calc_action_geometry(main_win, view_mode)
	local main_cfg = vim.api.nvim_win_get_config(main_win)
	local visible = actions_for_view(view_mode)
	local width = calc_action_width(visible)
	local height = math.max(#visible, 1)

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

-- =============================================================================
-- PROFILE PAGE HELPERS
-- =============================================================================

local BAR_CHARS = { "█", "▉", "▊", "▋", "▌", "▍", "▎", "▏" }

---@param ms number
---@return string
local function format_ms(ms)
	return string.format("%.2f", ms or 0)
end

---@param value number
---@param max number
---@param width integer  number of cells
---@return Beast.Packer.UI.Segment[]
local function render_bar(value, max, width)
	if not max or max <= 0 or width <= 0 or not value or value < 0 then
		return { { text = string.rep(" ", width), hl = nil } }
	end
	local ratio = math.min(value / max, 1)
	local total_eighths = math.floor(ratio * width * 8 + 0.5)
	local full = math.floor(total_eighths / 8)
	local remainder = total_eighths - full * 8
	local bar = string.rep(BAR_CHARS[1], full)
	if remainder > 0 and full < width then
		bar = bar .. BAR_CHARS[9 - remainder]
		full = full + 1
	end
	local pad = string.rep(" ", math.max(0, width - full))
	return {
		{ text = bar, hl = "BeastPackerBar" },
		{ text = pad, hl = nil },
	}
end

---@param title string
---@param right_text? string
---@param body_width integer
---@return Beast.Packer.UI.Segment[]
local function render_divider(title, right_text, body_width)
	local left = "  " .. title .. " "
	local right = right_text and (" " .. right_text .. " ") or ""
	local fill = math.max(0, body_width - vim.fn.strdisplaywidth(left) - vim.fn.strdisplaywidth(right))
	local segs = {
		{ text = left, hl = "BeastPackerH2" },
		{ text = string.rep("─", fill), hl = "BeastPackerSectionDivider" },
	}
	if right_text then
		table.insert(segs, { text = right, hl = "BeastPackerComment" })
	end
	return segs
end

---@param s string
---@param max integer
---@return string
local function truncate(s, max)
	if vim.fn.strdisplaywidth(s) <= max then
		return s
	end
	return string.sub(s, 1, math.max(0, max - 1)) .. "…"
end

---@return number
local function compute_total_loaded_ms()
	local sum = 0
	for _, prof in profile.iter() do
		sum = sum + (prof.total_ms or 0)
	end
	return sum
end

---@param main Beast.Packer.UI.MainView
---@return { name: string, prof: Beast.Packer.LoadProfile }[]
local function collect_loaded_profiles(main)
	local list = {}
	local threshold = main.profile_filter_ms or 0
	for name, prof in profile.iter() do
		if (prof.total_ms or 0) >= threshold then
			table.insert(list, { name = name, prof = prof })
		end
	end
	local mode = main.profile_sort or "total"
	if mode == "name" then
		table.sort(list, function(a, b)
			return a.name < b.name
		end)
	elseif mode == "packadd" then
		table.sort(list, function(a, b)
			return (a.prof.packadd_ms or 0) > (b.prof.packadd_ms or 0)
		end)
	elseif mode == "config" then
		table.sort(list, function(a, b)
			return (a.prof.config_ms or 0) > (b.prof.config_ms or 0)
		end)
	elseif mode == "chrono" then
		table.sort(list, function(a, b)
			local la, lb = a.prof.loaded_at or math.huge, b.prof.loaded_at or math.huge
			if la == lb then
				return a.name < b.name
			end
			return la < lb
		end)
	else -- "total"
		table.sort(list, function(a, b)
			return (a.prof.total_ms or 0) > (b.prof.total_ms or 0)
		end)
	end
	return list
end

---@param body_width integer
---@return Beast.Packer.UI.Segment[][]
local function render_timeline(body_width)
	---@type Beast.Packer.UI.Segment[][]
	local lines = {}
	table.insert(lines, render_divider("Timeline", nil, body_width))
	local phases = profile.phases or {}
	local order = { "early_cs", "pack_add" }
	local labels = {
		early_cs = "Early colorscheme",
		pack_add = "vim.pack.add",
	}
	local any = false
	for _, key in ipairs(order) do
		local p = phases[key]
		if p and p.ms and p.ms > 0 then
			any = true
			table.insert(lines, {
				{ text = "    ", hl = nil },
				{ text = config.ui.icons.loaded .. " ", hl = "BeastPackerCheckpoint" },
				{ text = labels[key] .. "  ", hl = "BeastPackerSummaryLabel" },
				{ text = string.format("%sms", format_ms(p.ms)), hl = "BeastPackerComment" },
			})
		end
	end
	if not any then
		table.insert(lines, { { text = "    (no phase data yet)", hl = "BeastPackerComment" } })
	end
	table.insert(lines, { { text = "", hl = nil } })
	return lines
end

---@param total_ms number
---@param loaded_count integer
---@param phase_total_ms number
---@param sort_label string
---@param filter_ms number
---@param grouped boolean
---@return Beast.Packer.UI.Segment[][]
local function render_summary(total_ms, loaded_count, phase_total_ms, sort_label, filter_ms, grouped)
	---@type Beast.Packer.UI.Segment[][]
	local lines = {}
	table.insert(lines, {
		{ text = "  Total plugin time: ", hl = "BeastPackerSummaryLabel" },
		{ text = format_ms(total_ms) .. " ms", hl = "BeastPackerTitle" },
		{ text = "    Plugins: ", hl = "BeastPackerSummaryLabel" },
		{ text = tostring(loaded_count), hl = nil },
		{ text = "    Phases: ", hl = "BeastPackerSummaryLabel" },
		{ text = format_ms(phase_total_ms) .. " ms", hl = nil },
	})
	local filter_text = (filter_ms and filter_ms > 0) and (">= " .. filter_ms .. "ms") or "off"
	table.insert(lines, {
		{ text = "  Sort: ", hl = "BeastPackerSummaryLabel" },
		{ text = sort_label, hl = nil },
		{ text = "    Filter: ", hl = "BeastPackerSummaryLabel" },
		{ text = filter_text, hl = nil },
		{ text = "    Group: ", hl = "BeastPackerSummaryLabel" },
		{ text = grouped and "by reason" or "off", hl = nil },
	})
	table.insert(lines, { { text = "", hl = nil } })
	return lines
end

---@param compact boolean
---@return Beast.Packer.UI.Segment[]
local function render_table_header(compact)
	if compact then
		return {
			{ text = "    ", hl = nil },
			{ text = string.format("%-26s%9s%9s%9s  %s", "NAME", "TOTAL", "PACKADD", "CONFIG", "REASON"), hl = "BeastPackerTableHeader" },
		}
	end
	return {
		{ text = "    ", hl = nil },
		{
			text = string.format("%-26s%9s%9s%7s%9s%14s  %s", "NAME", "TOTAL", "PACKADD", "INIT", "CONFIG", "%", "REASON"),
			hl = "BeastPackerTableHeader",
		},
	}
end

---@param item { name: string, prof: Beast.Packer.LoadProfile }
---@param max_total number
---@param total_ms number
---@param compact boolean
---@return Beast.Packer.UI.Segment[]
local function render_table_row(item, max_total, total_ms, compact)
	local prof = item.prof
	local total = prof.total_ms or 0
	local packadd = prof.packadd_ms or 0
	local init = prof.init_ms or 0
	local cfg = prof.config_ms or 0
	local segs = {
		{ text = "    ", hl = nil },
		{ text = string.format("%-26s", truncate(item.name, 26)), hl = "BeastPackerPlugin" },
		{ text = string.format("%8sms", format_ms(total)), hl = "BeastPackerComment" },
		{ text = string.format("%8sms", format_ms(packadd)), hl = "BeastPackerComment" },
	}
	if not compact then
		table.insert(segs, { text = string.format("%6s", format_ms(init)), hl = "BeastPackerComment" })
	end
	table.insert(segs, { text = string.format("%8sms", format_ms(cfg)), hl = "BeastPackerComment" })
	if not compact then
		table.insert(segs, { text = "  ", hl = nil })
		for _, b in ipairs(render_bar(total, max_total, 8)) do
			table.insert(segs, b)
		end
		local pct = (total_ms > 0) and math.floor(total / total_ms * 100 + 0.5) or 0
		table.insert(segs, { text = string.format(" %3d%%", pct), hl = "BeastPackerComment" })
	end
	local reason_seg = format_reason(prof.reason)
	if reason_seg then
		table.insert(segs, reason_seg)
	end
	return segs
end

---@param body_width integer
---@param items { name: string, prof: Beast.Packer.LoadProfile }[]
---@param total_ms number
---@param compact boolean
---@return Beast.Packer.UI.Segment[][]
local function render_plugins_table(body_width, items, total_ms, compact)
	---@type Beast.Packer.UI.Segment[][]
	local lines = {}
	table.insert(lines, render_divider("Plugins", "loaded " .. #items, body_width))
	if #items == 0 then
		table.insert(lines, { { text = "    (no plugins match the current filter)", hl = "BeastPackerComment" } })
		table.insert(lines, { { text = "", hl = nil } })
		return lines
	end
	local max_total = 0
	for _, it in ipairs(items) do
		if (it.prof.total_ms or 0) > max_total then
			max_total = it.prof.total_ms
		end
	end
	table.insert(lines, render_table_header(compact))
	for _, it in ipairs(items) do
		table.insert(lines, render_table_row(it, max_total, total_ms, compact))
	end
	table.insert(lines, { { text = "", hl = nil } })
	return lines
end

---@param items { name: string, prof: Beast.Packer.LoadProfile }[]
---@return table<string, { items: { name: string, prof: Beast.Packer.LoadProfile }[], total: number }>, string[]
local function group_by_reason(items)
	local groups = {}
	local order = {}
	for _, it in ipairs(items) do
		local r = it.prof.reason
		local key = r and r.type or "manual"
		if not groups[key] then
			groups[key] = { items = {}, total = 0 }
			table.insert(order, key)
		end
		table.insert(groups[key].items, it)
		groups[key].total = groups[key].total + (it.prof.total_ms or 0)
	end
	table.sort(order, function(a, b)
		return groups[a].total > groups[b].total
	end)
	return groups, order
end

---@param body_width integer
---@param items { name: string, prof: Beast.Packer.LoadProfile }[]
---@param total_ms number
---@param compact boolean
---@return Beast.Packer.UI.Segment[][]
local function render_grouped_plugins(body_width, items, total_ms, compact)
	---@type Beast.Packer.UI.Segment[][]
	local lines = {}
	local groups, order = group_by_reason(items)
	if #order == 0 then
		table.insert(lines, render_divider("Plugins", "loaded 0", body_width))
		table.insert(lines, { { text = "    (no plugins match the current filter)", hl = "BeastPackerComment" } })
		table.insert(lines, { { text = "", hl = nil } })
		return lines
	end
	for _, key in ipairs(order) do
		local g = groups[key]
		local label = key:sub(1, 1):upper() .. key:sub(2)
		local right = string.format("%d • %sms", #g.items, format_ms(g.total))
		table.insert(lines, render_divider(label, right, body_width))
		table.insert(lines, render_table_header(compact))
		local max_total = 0
		for _, it in ipairs(g.items) do
			if (it.prof.total_ms or 0) > max_total then
				max_total = it.prof.total_ms
			end
		end
		for _, it in ipairs(g.items) do
			table.insert(lines, render_table_row(it, max_total, total_ms, compact))
		end
		table.insert(lines, { { text = "", hl = nil } })
	end
	return lines
end

---@param body_width integer
---@return Beast.Packer.UI.Segment[][]
local function render_not_loaded(body_width)
	local pending = {}
	for _, spec in pairs(state.plugins) do
		if state.installed_plugins[spec.name] and not state.loaded_plugins[spec.name] then
			table.insert(pending, spec)
		end
	end
	---@type Beast.Packer.UI.Segment[][]
	local lines = {}
	if #pending == 0 then
		return lines
	end
	table.sort(pending, function(a, b)
		return a.name < b.name
	end)
	table.insert(lines, render_divider("Not loaded", tostring(#pending), body_width))
	for _, spec in ipairs(pending) do
		---@type Beast.Packer.UI.Segment[]
		local segs = {
			{ text = "    ", hl = nil },
			{ text = string.format("%-30s", truncate(spec.name, 30)), hl = "BeastPackerPlugin" },
		}
		local trigger
		if type(spec.lazy) == "table" then
			local lazy = spec.lazy
			local function first_of(v)
				if type(v) == "string" then
					return v
				end
				if type(v) == "table" then
					return v[1]
				end
				return nil
			end
			if lazy.event then
				trigger = { text = "  " .. config.ui.icons.event .. (first_of(lazy.event) or "event"), hl = "BeastPackerTriggerEvent" }
			elseif lazy.cmd then
				trigger = { text = "  " .. config.ui.icons.cmd .. (first_of(lazy.cmd) or "cmd"), hl = "BeastPackerTriggerCmd" }
			elseif lazy.keys then
				local k = first_of(lazy.keys)
				if type(k) == "table" then
					k = k[1] or k.lhs
				end
				trigger = { text = "  " .. config.ui.icons.keys .. (k or "keys"), hl = "BeastPackerTriggerKeys" }
			elseif lazy.module then
				trigger = { text = "  " .. config.ui.icons.module .. (first_of(lazy.module) or "?"), hl = "BeastPackerTriggerModule" }
			elseif lazy.filetype then
				trigger = { text = "  " .. config.ui.icons.filetype .. (first_of(lazy.filetype) or "ft"), hl = "BeastPackerTriggerFiletype" }
			elseif lazy.path then
				trigger = { text = "  " .. config.ui.icons.path .. (first_of(lazy.path) or "path"), hl = "BeastPackerTriggerPath" }
			end
		elseif spec.lazy == false then
			trigger = { text = "  " .. config.ui.icons.eager .. "Eager", hl = "BeastPackerTriggerEager" }
		else
			trigger = { text = "  " .. config.ui.icons.lazy .. "Manual", hl = "BeastPackerComment" }
		end
		if trigger then
			table.insert(segs, trigger)
		end
		table.insert(lines, segs)
	end
	table.insert(lines, { { text = "", hl = nil } })
	return lines
end

function Main._render_profile(main)
	-- stylua: ignore
	if not main:is_valid() then return end

	local win_w = vim.api.nvim_win_get_width(main.win)
	local body_width = math.max(40, win_w - 4)
	local compact = win_w < 100

	local items = collect_loaded_profiles(main)
	local total_ms = compute_total_loaded_ms()
	local phase_total_ms = 0
	for _, p in pairs(profile.phases or {}) do
		phase_total_ms = phase_total_ms + (p.ms or 0)
	end

	local sort_label = main.profile_sort or "total"

	---@type Beast.Packer.UI.Segment[][]
	local lines_segments = { { { text = "", hl = nil } } }

	for _, l in ipairs(render_summary(total_ms, #items, phase_total_ms, sort_label, main.profile_filter_ms or 0, main.profile_group_by_reason or false)) do
		table.insert(lines_segments, l)
	end

	for _, l in ipairs(render_timeline(body_width)) do
		table.insert(lines_segments, l)
	end

	if main.profile_group_by_reason then
		for _, l in ipairs(render_grouped_plugins(body_width, items, total_ms, compact)) do
			table.insert(lines_segments, l)
		end
	else
		for _, l in ipairs(render_plugins_table(body_width, items, total_ms, compact)) do
			table.insert(lines_segments, l)
		end
	end

	for _, l in ipairs(render_not_loaded(body_width)) do
		table.insert(lines_segments, l)
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
	table.insert(lines_segments, { { text = "  S - Toggle sort", hl = "BeastPackerComment" } })
	table.insert(lines_segments, { { text = "  F - Cycle filter (>= 0/1/5/10/50 ms)", hl = "BeastPackerComment" } })
	table.insert(lines_segments, { { text = "  G - Toggle group by load reason", hl = "BeastPackerComment" } })
	table.insert(lines_segments, { { text = "  P - Toggle profile view", hl = "BeastPackerComment" } })
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
	local width, height, row, col = calc_action_geometry(main.win, main.view_mode or "main")

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

	local width, height, row, col = calc_action_geometry(main.win, main.view_mode or "main")

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
---@param view_mode string
function Action.render(action, view_mode)
  -- stylua: ignore
  if not action:is_valid() then return end

	vim.api.nvim_buf_clear_namespace(action.buf, action.ns, 0, -1)

	local visible = actions_for_view(view_mode)
	local max_keys_width = get_max_keys_width(visible)

	-- Clear buffer to match visible action count
	vim.bo[action.buf].modifiable = true
	local lines = {}
	for _ = 1, math.max(#visible, 1) do
		table.insert(lines, "")
	end
	vim.api.nvim_buf_set_lines(action.buf, 0, -1, false, lines)
	vim.bo[action.buf].modifiable = false

	for i, a in ipairs(visible) do
		local line0 = i - 1
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
		Action.layout(state_data.action, state_data.main)
		Action.render(state_data.action, state_data.main.view_mode or "main")
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
		render_state()
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

local PROFILE_SORT_CYCLE = { "total", "packadd", "config", "name", "chrono" }
local FILTER_THRESHOLDS = { 0, 1, 5, 10, 50 }

local function next_in_cycle(value, cycle)
	for i, v in ipairs(cycle) do
		if v == value then
			return cycle[(i % #cycle) + 1]
		end
	end
	return cycle[1]
end

function _actions_handler.sort()
	if not state_data:is_valid() then
		return
	end
	local main = state_data.main
	if main.view_mode == "profile" then
		main.profile_sort = next_in_cycle(main.profile_sort or "total", PROFILE_SORT_CYCLE)
	else
		main.sort_mode = main.sort_mode == "name" and "time" or "name"
	end
	render_state()
end

function _actions_handler.filter_cycle()
	if not state_data:is_valid() then
		return
	end
	state_data.main.profile_filter_ms = next_in_cycle(state_data.main.profile_filter_ms or 0, FILTER_THRESHOLDS)
	render_state()
end

function _actions_handler.group_toggle()
	if not state_data:is_valid() then
		return
	end
	state_data.main.profile_group_by_reason = not state_data.main.profile_group_by_reason
	render_state()
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
