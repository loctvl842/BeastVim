-- =============================================================================
-- Beast key hint — Helix-style press-and-wait
-- =============================================================================
-- Built on top of `Key.managed` (our single source of truth) so we never scrape
-- nvim_get_keymap, never rebuild per-buffer, never run a polling timer.
--
-- Lifecycle:
--   setup() registers two-ish trigger keymaps (one per configured prefix x mode).
--   On press → start() opens a Helix-style float and runs a getchar loop.
--   On resolve → execute() suspends the trigger, feedkeys() the full sequence,
--                schedules trigger re-registration on the next tick.
--   Index cached lazily; invalidated by `BeastKeysChanged` User autocmd.
-- =============================================================================

local View = require("beast.libs.view")
local core = require("beast.libs.key.core")

local M = {}

---@class Beast.Key.HintView : Beast.View
local HintView = View:extend()

---@class Beast.Key.Hint.Node
---@field children table<string, Beast.Key.Hint.Node>
---@field keymap? Beast.Keymap   -- present at leaves
---@field group? string          -- group label if any
---@field key string             -- the single key segment that leads here

---@class Beast.Key.Hint.State
---@field mode string
---@field trigger string         -- raw trigger (e.g. "<leader>")
---@field trigger_segs string[]  -- pre-split trigger segments (e.g. { " " })
---@field sequence string[]      -- keys pressed *after* the trigger (translated)
---@field bufnr integer          -- buffer the hint was opened from
---@field win_before integer
---@field count? integer         -- captured v:count at start
---@field register? string       -- captured v:register at start
---@field done? boolean          -- set by close_window so deferred callbacks no-op
---@field delay_timer? userdata  -- libuv timer used for cfg.delay
---@field view? Beast.View

---@type Beast.Key.HintConfig?
local cfg = nil

---@type table<string, Beast.Key.Hint.Node>?  -- key: mode → tree root
local index_cache = nil

---@type table<string, boolean>  -- "mode\0trigger" → registered
local registered = {}

-- Recursion guard: count successive start() invocations; reset by a timer.
local recursion_count = 0
local recursion_timer = nil

local ns = vim.api.nvim_create_namespace("BeastKeyHint")

-- =============================================================================
-- Key utilities
-- =============================================================================

---Split an lhs into a list of normalised key tokens via keytrans+termcodes.
---e.g. "<leader>fa" with mapleader=" " → { " ", "f", "a" }
---     "<C-w>h"                         → { "<C-W>", "h" }
---@param lhs string
---@return string[]
local function split_keys(lhs)
	local termcoded = vim.api.nvim_replace_termcodes(lhs, true, true, true)
	local tokens = {}
	local i = 1
	local n = #termcoded
	while i <= n do
		local c = termcoded:sub(i, i)
		-- Special keys begin with 0x80 (K_SPECIAL) and span 3 bytes.
		if c == "\x80" then
			local raw = termcoded:sub(i, i + 2)
			table.insert(tokens, vim.fn.keytrans(raw))
			i = i + 3
		else
			table.insert(tokens, vim.fn.keytrans(c))
			i = i + 1
		end
	end
	return tokens
end

---Translate a single key from getcharstr() to canonical form (e.g. "<Esc>").
---@param key string
---@return string
local function key_label(key)
	return vim.fn.keytrans(key)
end

-- =============================================================================
-- Index (prefix tree)
-- =============================================================================

local function new_node(key)
	return { children = {}, key = key or "" }
end

---@return table<string, Beast.Key.Hint.Node>
local function build_index()
	---@type table<string, Beast.Key.Hint.Node>
	local roots = {}

	for _, km in pairs(core.managed) do
		if type(km) == "table" and km.lhs and km.mode then
			local root = roots[km.mode]
			if not root then
				root = new_node()
				roots[km.mode] = root
			end
			local segs = split_keys(km.lhs)
			local node = root
			for _, seg in ipairs(segs) do
				local child = node.children[seg]
				if not child then
					child = new_node(seg)
					node.children[seg] = child
				end
				node = child
			end
			if km.rhs ~= nil then
				node.keymap = km
			end
			if km.group then
				node.group = km.group
			end
		end
	end

	return roots
end

local function get_index()
	if not index_cache then
		index_cache = build_index()
	end
	return index_cache
end

---Modes that should fall back to a sibling mode in the index.
---Visual `x` mappings are also commonly registered as `v` (visual+select).
local MODE_FALLBACK = { x = "v", s = "v" }

---Walk the tree following a sequence of translated keys.
---@param mode string
---@param segs string[]
---@return Beast.Key.Hint.Node?
local function walk(mode, segs)
	local idx = get_index()
	local root = idx[mode] or idx[MODE_FALLBACK[mode] or mode]
	if not root then
		return nil
	end
	local node = root
	for _, seg in ipairs(segs) do
		node = node.children and node.children[seg]
		if not node then
			return nil
		end
	end
	return node
end

---Returns true if any descendant (or this node) holds a keymap reachable from bufnr.
---@param node Beast.Key.Hint.Node
---@param bufnr integer
---@return boolean
local function reachable(node, bufnr)
	if node.keymap then
		local b = node.keymap.buffer
		if b == nil or b == false then
			return true
		end
		if type(b) == "number" then
			return b == bufnr
		end
	end
	for _, c in pairs(node.children) do
		if reachable(c, bufnr) then
			return true
		end
	end
	return false
end

---Filter children of a node to those that are reachable from the current buffer.
---@param node Beast.Key.Hint.Node
---@param bufnr integer
---@return { key: string, child: Beast.Key.Hint.Node }[]
local function visible_children(node, bufnr)
	local out = {}
	for key, child in pairs(node.children) do
		if reachable(child, bufnr) then
			table.insert(out, { key = key, child = child })
		end
	end
	-- Sort: groups last, alphanum.
	table.sort(out, function(a, b)
		local ag = a.child.group ~= nil and not a.child.keymap
		local bg = b.child.group ~= nil and not b.child.keymap
		if ag ~= bg then
			return not ag
		end
		return a.key < b.key
	end)
	return out
end

-- =============================================================================
-- Window
-- =============================================================================

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
local function open_or_update(state, title, items)
	local win_cfg = cfg.win
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

local function close_window(state)
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

-- =============================================================================
-- Render + loop
-- =============================================================================

---@param state Beast.Key.Hint.State
---@return Beast.Key.Hint.Node?
local function walk_state(state)
	local full = {}
	for _, s in ipairs(state.trigger_segs) do
		table.insert(full, s)
	end
	for _, s in ipairs(state.sequence) do
		table.insert(full, s)
	end
	local node = walk(state.mode, full)
	if not node then
		return nil
	end
	-- Reject if unreachable in the current buffer.
	if not reachable(node, state.bufnr) then
		return nil
	end
	return node
end

---@param state Beast.Key.Hint.State
local function render(state)
	local node = walk_state(state)
	if not node then
		return false
	end
	local items = visible_children(node, state.bufnr)
	local crumbs = { state.trigger }
	for _, k in ipairs(state.sequence) do
		table.insert(crumbs, k)
	end
	local title = " " .. table.concat(crumbs, " ") .. " "
	open_or_update(state, title, items)
	vim.cmd("redraw")
	return true
end

---@param state Beast.Key.Hint.State
---@return string|nil sequence_to_feed -- canonical sequence (e.g. "<leader>ff") or nil to cancel
local function loop(state)
	-- Open immediately when delay == 0; otherwise schedule below.
	if (cfg.delay or 0) <= 0 then
		render(state)
	end

	local opened = (cfg.delay or 0) <= 0
	if not opened then
		state.delay_timer = (vim.uv or vim.loop).new_timer()
		state.delay_timer:start(
			cfg.delay,
			0,
			vim.schedule_wrap(function()
				if not opened and not state.done then
					opened = true
					render(state)
				end
			end)
		)
	end

	local function stop_timer()
		if state.delay_timer then
			state.delay_timer:stop()
			state.delay_timer:close()
			state.delay_timer = nil
		end
	end

	while true do
		local ok, raw = pcall(vim.fn.getcharstr)
		if not ok or raw == "" then
			stop_timer()
			return nil
		end

		local label = key_label(raw)

		-- Cancel: <Esc> or <C-c>
		if label == "<Esc>" or raw == "\003" then
			stop_timer()
			return nil
		end

		-- Backspace: pop one level (stay open at root).
		if label == "<BS>" then
			if #state.sequence > 0 then
				table.remove(state.sequence)
				if opened then
					render(state)
				end
			end
		else
			-- Descend
			table.insert(state.sequence, label)
			local node = walk_state(state)
			if not node then
				-- No match: feed the raw sequence verbatim.
				stop_timer()
				return state.trigger .. table.concat(state.sequence, "")
			end
			-- Executable leaf with no further children → execute.
			if node.keymap and node.keymap.rhs ~= nil and not next(node.children) then
				stop_timer()
				return state.trigger .. table.concat(state.sequence, "")
			end
			-- Prefix node (with or without an executable rhs): keep waiting.
			-- Note: Phase 1 does not implement timeoutlen-based auto-execution
			-- for prefix-and-leaf collisions; deferred to a later phase.
			if not opened then
				opened = true
			end
			render(state)
		end
	end
end

-- =============================================================================
-- Execute (suspend & feed)
-- =============================================================================

---Temporarily remove trigger keymaps so feedkeys() resolves through normal maps,
---then re-register them on the next tick.
---@param state Beast.Key.Hint.State
---@param keys string
local function suspend_and_feed(state, keys)
	-- Tear down all registered triggers.
	local to_restore = {}
	for k, _ in pairs(registered) do
		local mode, trig = k:match("^(.-)\0(.*)$")
		if mode and trig then
			pcall(vim.keymap.del, mode, trig)
			table.insert(to_restore, { mode = mode, trig = trig })
		end
	end
	registered = {}

	-- Build the prefix to restore: register and count. Visual selection is
	-- preserved naturally because we never leave visual mode while the hint
	-- is open (hint window is non-focusable and not entered).
	local prefix = ""
	if state.count and state.count > 0 then
		prefix = prefix .. tostring(state.count)
	end
	if state.register and state.register ~= "" then
		prefix = '"' .. state.register .. prefix
	end

	local termcoded = vim.api.nvim_replace_termcodes(prefix .. keys, true, true, true)
	vim.api.nvim_feedkeys(termcoded, "m", false)

	vim.schedule(function()
		for _, r in ipairs(to_restore) do
			M.register_trigger(r.mode, r.trig)
		end
	end)
end

-- =============================================================================
-- Trigger registration
-- =============================================================================

---@param mode string
---@param trigger string  -- raw form e.g. "<leader>"
function M.register_trigger(mode, trigger)
	local key = mode .. "\0" .. trigger
	if registered[key] then
		return
	end

	-- Collision check: skip if another (non-Beast) map already owns it.
	local existing = vim.fn.maparg(trigger, mode, false, true)
	if type(existing) == "table" and existing.lhs and existing.desc ~= "beast-key-hint-trigger" then
		vim.notify(string.format("[beast.key.hint] skipping trigger %q (mode=%s): already mapped", trigger, mode), vim.log.levels.WARN)
		return
	end

	vim.keymap.set(mode, trigger, function()
		M.start(mode, trigger)
	end, {
		silent = true,
		nowait = true,
		desc = "beast-key-hint-trigger",
	})
	registered[key] = true
end

---Entry-point called by the trigger keymap.
---@param mode string
---@param trigger string
function M.start(mode, trigger)
	-- Recursion guard: if our trigger gets re-entered too many times in quick
	-- succession (e.g. user's keymap feeds <leader> recursively), bail out.
	recursion_count = recursion_count + 1
	if recursion_count > 20 then
		vim.notify("[beast.key.hint] recursion limit hit; aborting", vim.log.levels.WARN)
		recursion_count = 0
		return
	end
	if not recursion_timer then
		recursion_timer = (vim.uv or vim.loop).new_timer()
		recursion_timer:start(
			500,
			0,
			vim.schedule_wrap(function()
				recursion_count = 0
				if recursion_timer then
					recursion_timer:close()
					recursion_timer = nil
				end
			end)
		)
	end

	-- Skip during macro recording or replay: feed the trigger verbatim so the
	-- macro records the literal keys (without opening our hint).
	if vim.fn.reg_recording() ~= "" or vim.fn.reg_executing() ~= "" then
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(trigger, true, true, true), "n", false)
		return
	end

	-- Skip when there is pending input queued (e.g. inside `:norm`): replay
	-- the trigger so normal-mode mappings resolve as the user wrote them.
	if vim.fn.getchar(1) ~= 0 then
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(trigger, true, true, true), "n", false)
		return
	end

	local state = {
		mode = mode,
		trigger = trigger,
		trigger_segs = split_keys(trigger),
		sequence = {},
		bufnr = vim.api.nvim_get_current_buf(),
		win_before = vim.api.nvim_get_current_win(),
		count = vim.v.count,
		register = vim.v.register,
	}

	-- Visual selection is preserved across the hint: the floating window is
	-- non-focusable and opened with enter=false, so the cursor stays in the
	-- user's window and visual mode remains active while getcharstr blocks.

	-- Run the modal loop under xpcall so any error still tears down the
	-- floating window cleanly and lets the trigger be re-registered.
	local ok, feed = xpcall(loop, debug.traceback, state)
	close_window(state)

	if not ok then
		vim.notify("[beast.key.hint] error: " .. tostring(feed), vim.log.levels.ERROR)
		return
	end

	if feed and feed ~= "" then
		suspend_and_feed(state, feed)
	end
end

-- =============================================================================
-- Setup
-- =============================================================================

---@param hint_cfg Beast.Key.HintConfig
function M.setup(hint_cfg)
	cfg = hint_cfg

	-- Invalidate index whenever managed keymaps change.
	local group = vim.api.nvim_create_augroup("BeastKeyHint", { clear = true })
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "BeastKeysChanged",
		callback = function()
			index_cache = nil
		end,
	})

	for _, trigger in ipairs(cfg.triggers) do
		for _, mode in ipairs(cfg.modes) do
			M.register_trigger(mode, trigger)
		end
	end
end

-- =============================================================================
-- Internal hooks (tests + bench)
-- =============================================================================

---Internal: exposed for `scripts/bench-key-hint.lua` and `tests/`.
---Do not depend on this API outside of those.
M._internal = {
	build_index = build_index,
	walk = walk,
	visible_children = visible_children,
	split_keys = split_keys,
	---Render the hint once at the given prefix (no getchar loop).
	---@param mode string
	---@param trigger string
	---@param sequence string[]
	render_once = function(mode, trigger, sequence)
		local state = {
			mode = mode,
			trigger = trigger,
			trigger_segs = split_keys(trigger),
			sequence = sequence or {},
			bufnr = vim.api.nvim_get_current_buf(),
			win_before = vim.api.nvim_get_current_win(),
		}
		render(state)
		close_window(state)
	end,
	invalidate_cache = function()
		index_cache = nil
	end,
}

return M
