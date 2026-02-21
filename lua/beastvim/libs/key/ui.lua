local M = {}

local cfg
-- filters/state
local filter_mode = "all" -- one of: all | n|v|i|x|s|o|c|t
local beast_only = true
local mode_order = { "n", "v", "i", "x", "s", "o", "c", "t" }
local expanded = {} -- map id (lhs) -> true when showing source

function M.defaults()
	return {
		border = "rounded",
		width = 0.7,
		height = 0.7,
		backdrop = 30,
		keymaps = {
			close = { "q", "<Esc>" },
		},
	}
end

local function create_layout()
	local width = math.floor(vim.o.columns * cfg.width)
	local height = math.floor(vim.o.lines * cfg.height)
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	-- ==========================================================================
	-- Backdrop
	-- ==========================================================================
	local backdrop_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[backdrop_buf].buftype = "nofile"
	vim.bo[backdrop_buf].bufhidden = "wipe"
	vim.bo[backdrop_buf].filetype = "beast_backdrop"

	local backdrop_win = vim.api.nvim_open_win(backdrop_buf, false, {
		relative = "editor",
		row = 0,
		col = 0,
		width = vim.o.columns,
		height = vim.o.lines,
		style = "minimal",
		focusable = false,
		zindex = 1,
	})
	Util.wo(backdrop_win, "winblend", cfg.backdrop)

	-- ==========================================================================
	-- Main floating window
	-- ==========================================================================
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "beast_key"

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = cfg.border or "rounded",
		zindex = 2,
	})
	Util.wo(win, "wrap", false)
	Util.wo(win, "number", false)
	Util.wo(win, "relativenumber", false)
	Util.wo(win, "signcolumn", "no")

	-- ==========================================================================
	-- Close logic (shared)
	-- ==========================================================================
	local function close_all()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
		if vim.api.nvim_win_is_valid(backdrop_win) then
			vim.api.nvim_win_close(backdrop_win, true)
		end
	end

	-- Keymaps
	for _, key in ipairs(cfg.keymaps.close) do
		vim.keymap.set("n", key, close_all, {
			buffer = buf,
			silent = true,
			nowait = true,
		})
	end

	-- Auto-close if user switches windows
	vim.api.nvim_create_autocmd("WinLeave", {
		once = true,
		callback = close_all,
	})

	-- Reposition backdrop + main float on resize
	vim.api.nvim_create_autocmd("VimResized", {
		callback = function()
			if not vim.api.nvim_win_is_valid(win) then
				return true -- delete autocmd
			end
			vim.api.nvim_win_set_config(backdrop_win, {
				relative = "editor",
				row = 0,
				col = 0,
				width = vim.o.columns,
				height = vim.o.lines,
			})
			local new_width = math.floor(vim.o.columns * cfg.width)
			local new_height = math.floor(vim.o.lines * cfg.height)
			vim.api.nvim_win_set_config(win, {
				relative = "editor",
				row = math.floor((vim.o.lines - new_height) / 2),
				col = math.floor((vim.o.columns - new_width) / 2),
				width = new_width,
				height = new_height,
			})
		end,
	})

	return {
		buf = buf,
		win = win,
		close = close_all,
	}
end

-- Put a vertical "actions column" at the top-right of the float using extmarks.
-- Draw one action per line, right-aligned, starting at `start_line0`.
local function set_topright_actions_column(buf, start_line0, actions)
	local ns = vim.api.nvim_create_namespace("beast_key_actions")
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

	for i, a in ipairs(actions) do
		local line0 = start_line0 + (i - 1)
		local line_count = vim.api.nvim_buf_line_count(buf)

		-- Ensure anchor line exists
		if line0 >= line_count then
			vim.bo[buf].modifiable = true
			for _ = line_count, line0 do
				vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "" })
			end
			vim.bo[buf].modifiable = false
		end

		vim.api.nvim_buf_set_extmark(buf, ns, line0, 0, {
			virt_text = {
				{ " " .. a.key .. " ", a.key_hl or "ErrorMsg" }, -- standout key
				{ " " .. a.label, a.label_hl or "Comment" }, -- softer label
			},
			virt_text_pos = "right_align",
		})
	end
end

local function create_actions_layout(main_win, actions, opts)
	opts = opts or {}
	local ns = vim.api.nvim_create_namespace("beast_key_actions")

	-- actions buffer (separate from content buffer -> won't scroll)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false

	-- Decide overlay size (simple + robust)
	local height = #actions
  local max_len = 0
  for _, a in ipairs(actions) do max_len = math.max(max_len, #a.label) end
	local width = max_len + 4 -- Width of the longest label + padding

	local win = vim.api.nvim_open_win(buf, false, {
		relative = "win",
		win = main_win,
		row = opts.row or 0,
		col = 0, -- set after we know main width
		width = width,
		height = height,
		style = "minimal",
		border = opts.border or "none",
		focusable = false,
		zindex = (opts.zindex or 50) + 1,
		noautocmd = true,
	})
	Util.wo(win, "winblend", 0)

	-- Position it at top-right INSIDE the main float
	local function reposition()
		if not (vim.api.nvim_win_is_valid(main_win) and vim.api.nvim_win_is_valid(win)) then
			return
		end
		local main_cfg = vim.api.nvim_win_get_config(main_win)
		local main_w = main_cfg.width
		local margin_right = opts.margin_right or 0
		local col = math.max(0, main_w - width - margin_right)
		vim.api.nvim_win_set_config(win, {
			relative = "win",
			win = main_win,
			row = opts.row or 0,
			col = col,
			width = width,
			height = height,
		})
	end

	reposition()

	-- Render actions into overlay buffer using your existing function
	set_topright_actions_column(buf, 0, actions, ns)

	local function close()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
	end

	-- Overlay manages its own lifecycle
	vim.api.nvim_create_autocmd("VimResized", {
		callback = function()
			reposition()
		end,
	})

	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(main_win),
		callback = function()
			close()
		end,
	})

	return {
		buf = buf,
		win = win,
		ns = ns,
		reposition = reposition,
		close = close,
	}
end

local function rhs_to_string(rhs)
  --stylua: ignore start
  if type(rhs) == "string" then return rhs end
  if type(rhs) == "function" then return "<fn>" end
  if rhs == false then return "<del>" end
  if rhs == nil then return "" end
  return tostring(rhs)
end

local function collect_beast_managed()
	local list = {}
	for _, km in pairs(Key.managed) do
		table.insert(list, {
			source = "Beast",
			mode = km.mode,
			lhs = km.lhs,
			rhs = rhs_to_string(km.rhs),
			desc = km.desc,
			group = km.group,
			buffer = nil,
		})
	end
	return list
end

--- Normalize action labels to the same length by adding spaces,
--- so that the key is always left-aligned.
local function normalize_length(actions, field)
  -- stylua: ignore start
  local max_len = 0
  for _, a in ipairs(actions) do max_len = math.max(max_len, #a[field]) end
  for _, a in ipairs(actions) do a[field] = a[field] .. string.rep(" ", max_len - #a[field]) end
  return actions
end

local function filtered_entries()
	local entries = {}
	if beast_only then
		entries = collect_beast_managed()
	else
		entries = collect_nvim_maps()
		-- annotate managed ones for visibility
		local managed = {}
		for _, km in pairs(require("beastvim.libs.keys").managed) do
			managed[(km.mode or "n") .. "\t" .. km.lhs] = true
		end
		for _, e in ipairs(entries) do
			if managed[e.mode .. "\t" .. e.lhs] and e.source ~= "BUF" then
				e.source = "Beast"
			end
		end
	end

	-- filter by mode
	if filter_mode ~= "all" then
		local out = {}
		for _, e in ipairs(entries) do
			if e.mode == filter_mode then
				table.insert(out, e)
			end
		end
		entries = out
	end

	table.sort(entries, function(a, b)
		if a.mode == b.mode then
			if a.lhs == b.lhs then
				return (a.source or "") < (b.source or "")
			end
			return a.lhs < b.lhs
		end
		local ai, bi = 9, 9
		for i, m in ipairs(mode_order) do
			if m == a.mode then
				ai = i
			end
			if m == b.mode then
				bi = i
			end
		end
		return ai < bi
	end)
	return entries
end

local function get_actions()
	local actions = {
    -- stylua: ignore start
    { key = "I", label = "Install",  key_hl = "DiagnosticError", label_hl = "Comment" },
    { key = "U", label = "Update",   key_hl = "DiagnosticWarn",  label_hl = "Comment" },
    { key = "S", label = "Sync",     key_hl = "DiagnosticInfo",  label_hl = "Comment" },
    { key = "X", label = "Clean",    key_hl = "DiagnosticHint",  label_hl = "Comment" },
    { key = "?", label = "Help",     key_hl = "Question",        label_hl = "Comment" },
	}
	return normalize_length(actions, "label")
end

local function render_lines(buf, lines_segments)
	local lines = {}
	local ns = vim.api.nvim_create_namespace("beastkeys")
	for _, segs in ipairs(lines_segments) do
		local s = ""
    --stylua: ignore
    for _, seg in ipairs(segs) do s = s .. seg.text end
		table.insert(lines, s)
	end
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	for i, segs in ipairs(lines_segments) do
		local col = 0
		for _, seg in ipairs(segs) do
			if seg.hl then
				vim.api.nvim_buf_set_extmark(buf, ns, i - 1, col, { end_col = col + #seg.text, hl_group = seg.hl })
			end
			col = col + #seg.text
		end
	end
end

local function build_content_lines(entries)
	local lines = {}
	local title = "  🦁 Keymaps"
	table.insert(lines, { { text = title, hl = "BeastH2" } })
	local mlabel = filter_mode == "all" and "All" or filter_mode
	local blabel = beast_only and "Beast" or "All"
	local stats = string.format("  Mode: %s   Source: %s", mlabel, blabel)

	table.insert(lines, { { text = stats, hl = "BeastComment" } })
	table.insert(lines, { { text = "", hl = nil } })

	if #entries == 0 then
		table.insert(lines, { { text = "  (no keymaps)", hl = "BeastComment" } })
		return lines
	end

	-- Group entries by their group name
	local by_group = {}
	local group_order = {}
	for _, e in ipairs(entries) do
		local gname = (e.group and #e.group > 0) and e.group or "Ungrouped"
		if not by_group[gname] then
			by_group[gname] = {}
			table.insert(group_order, gname)
		end
		table.insert(by_group[gname], e)
	end

    -- stylua: ignore
    table.sort(group_order, function(a, b)
      if a == "Ungrouped" then return false end
      if b == "Ungrouped" then return true end
      return a:lower() < b:lower()
    end)
	for _, gname in ipairs(group_order) do
		local show_header = gname ~= "Ungrouped"
      -- stylua: ignore
      if show_header then table.insert(lines, { { text = "  " .. gname, hl = "BeastGroup" } }) end

		-- Within group, collapse duplicates by lhs and aggregate modes
		local groups = {}
		local order = {}
		for _, e in ipairs(by_group[gname]) do
			local id = (e.lhs or "")
			if not groups[id] then
				groups[id] = { lhs = e.lhs, items = {}, modes = {} }
				table.insert(order, id)
			end
			table.insert(groups[id].items, e)
			if e.mode then
				groups[id].modes[e.mode] = true
			end
		end

		-- Pre-compute mode labels and primary items
		local prefix = show_header and "    " or "  "
		local computed = {}
		for _, id in ipairs(order) do
			local g = groups[id]
			local mode_label = ""
			for _, m in ipairs(mode_order) do
				if g.modes[m] then
					mode_label = mode_label .. m
				end
			end
			if mode_label == "" then
				mode_label = "?"
			end
			local primary = g.items[1]
			for _, it in ipairs(g.items) do
				if it.desc and #it.desc > 0 then
					primary = it
					break
				end
			end
			table.insert(computed, { id = id, g = g, mode_label = mode_label, lhs = g.lhs or "", primary = primary })
		end

		-- Pad mode and lhs columns for alignment
		normalize_length(computed, "mode_label")
		normalize_length(computed, "lhs")

		-- Build rows
		for _, c in ipairs(computed) do
			local row = {}
			table.insert(row, { text = prefix .. string.format("[%s] ", c.mode_label), hl = "BeastKeys" })
			table.insert(row, { text = c.lhs, hl = nil })
			if c.primary.desc and #c.primary.desc > 0 then
				table.insert(row, { text = "  - ", hl = "BeastComment" })
				table.insert(row, { text = c.primary.desc, hl = "BeastComment" })
			end
			if #c.g.items > 1 then
				table.insert(row, { text = string.format("  ×%d", #c.g.items), hl = "BeastComment" })
			end
			if expanded[c.id] and #c.g.items == 1 and c.primary.src and #c.primary.src > 0 then
				table.insert(row, { text = "  (", hl = "BeastComment" })
				table.insert(row, { text = c.primary.src, hl = "BeastComment" })
				table.insert(row, { text = ")", hl = "BeastComment" })
			end
			table.insert(lines, row)

			if expanded[c.id] and #c.g.items > 1 then
				for _, it in ipairs(c.g.items) do
					local child = {}
					table.insert(child, { text = prefix .. "  • ", hl = "BeastComment" })
					local label = (it.desc and #it.desc > 0) and it.desc or "(no description)"
					table.insert(child, { text = label, hl = "BeastComment" })
					if it.src and #it.src > 0 then
						table.insert(child, { text = "  (", hl = "BeastComment" })
						table.insert(child, { text = it.src, hl = "BeastComment" })
						table.insert(child, { text = ")", hl = "BeastComment" })
					end
					table.insert(lines, child)
				end
			end
		end
	end
	return lines
end

---@param float table { buf: integer, win: integer }
local function render_layout(float)
	create_actions_layout(float.win, get_actions(), {
		width = 26,
		margin_right = 0,
		zindex = 60,
	})
	local lines = build_content_lines(filtered_entries())
	render_lines(float.buf, lines)
end

function M.open()
	if cfg == nil then
		cfg = M.defaults()
	end

	local float = create_layout()
	render_layout(float)
end

function M.setup(opts)
	cfg = vim.tbl_deep_extend("force", M.defaults(), opts or {})
	-- do module wiring with cfg (keymaps, state, etc.)
end

function M.get()
	return cfg or M.defaults()
end

return M
