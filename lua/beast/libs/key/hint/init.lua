-- =============================================================================
-- Beast key hint — Helix-style press-and-wait
-- =============================================================================
-- Built on top of `Key.managed` (our single source of truth) so we never scrape
-- nvim_get_keymap, never rebuild per-buffer, never run a polling timer.
--
-- Lifecycle:
--   setup() registers trigger keymaps (one per configured prefix x mode).
--   On press → start() opens a Helix-style float and runs a getchar loop.
--   On resolve → suspend_and_feed() removes triggers, feedkeys() the full
--                sequence, schedules trigger re-registration on the next tick.
--   Index cached lazily; invalidated by `BeastKeysChanged` User autocmd.
-- =============================================================================

local config = require("beast.libs.key.config")
local index = require("beast.libs.key.hint.index")
local loop = require("beast.libs.key.hint.loop")
local window = require("beast.libs.key.hint.window")

local M = {}

---@class Beast.Key.Hint.State
---@field mode string
---@field trigger string         -- raw trigger (e.g. "<leader>")
---@field trigger_segs string[]  -- pre-split trigger segments (e.g. { " " })
---@field sequence string[]      -- keys pressed *after* the trigger (translated)
---@field bufnr integer          -- buffer the hint was opened from
---@field win_before integer
---@field count? integer         -- captured v:count at start
---@field register? string       -- captured v:register at start
---@field done? boolean          -- set by window.close so deferred callbacks no-op
---@field delay_timer? uv.uv_timer_t  -- libuv timer used for cfg.delay
---@field view? Beast.View.Instance

-- =============================================================================
-- Small helpers
-- =============================================================================

---@param s string
---@return string
local function termcodes(s)
	return vim.api.nvim_replace_termcodes(s, true, true, true)
end

---@param keys string
---@param flags string  -- e.g. "n", "in", "m"
local function feed(keys, flags)
	vim.api.nvim_feedkeys(termcodes(keys), flags, false)
end

---Convert a getchar() return value (number for plain ASCII, string for special
---keys) to a raw string suitable for keytrans.
---@param c integer|string
---@return string
local function getchar_to_str(c)
	return type(c) == "number" and vim.fn.nr2char(c) or c
end

-- =============================================================================
-- Module state
-- =============================================================================

---@type table<string, boolean>  -- "mode\0trigger" → registered
local registered = {}

-- Recursion guard: count successive start() invocations; reset by a timer.
local recursion_count = 0
local recursion_timer = nil

-- Autorepeat resume: when we delete a trigger keymap to let OS autorepeat
-- run natively, an on_key watcher tracks input activity and re-registers
-- the trigger only after input goes quiet (i.e. the user released the key).
-- This gives zero per-repeat overhead while the key is held: the trigger
-- keymap is gone for the entire hold, not re-armed every N ms.
local AUTOREPEAT_QUIET_MS = 50

---@class Beast.Key.Hint.ResumeWatch
---@field timer uv.uv_timer_t
---@field ns integer

---@type table<string, Beast.Key.Hint.ResumeWatch>
local autorepeat_watches = {}

---Delete the trigger keymap so subsequent OS-autorepeat presses execute
---natively (no Lua callback overhead). Use vim.on_key to detect when input
---goes quiet (key released) and re-register the trigger then.
---@param mode string
---@param trigger string
local function suspend_trigger_for_autorepeat(mode, trigger)
	local key = mode .. "\0" .. trigger
	if registered[key] then
		pcall(vim.keymap.del, mode, trigger)
		registered[key] = nil
	end

	-- Tear down any previous watch for this trigger.
	local existing = autorepeat_watches[key]
	if existing then
		existing.timer:stop()
		existing.timer:close()
		vim.on_key(nil, existing.ns)
		autorepeat_watches[key] = nil
	end

	local timer = assert((vim.uv or vim.loop).new_timer())
	local ns = vim.api.nvim_create_namespace("BeastKeyHintResume:" .. key)
	local watch = { timer = timer, ns = ns }
	autorepeat_watches[key] = watch

	local function resume()
		if autorepeat_watches[key] ~= watch then
			return
		end
		autorepeat_watches[key] = nil
		timer:stop()
		timer:close()
		vim.on_key(nil, ns)
		M.register_trigger(mode, trigger)
	end

	local schedule_resume = vim.schedule_wrap(resume)

	-- Each keystroke (including OS autorepeats of the held trigger) resets
	-- the quiet timer. When input stops, the timer fires and re-registers.
	vim.on_key(function()
		if autorepeat_watches[key] ~= watch then
			return
		end
		timer:stop()
		timer:start(AUTOREPEAT_QUIET_MS, 0, schedule_resume)
	end, ns)

	-- Kick the timer immediately so we still resume if no further keys arrive
	-- (e.g. the user released right after the autorepeat detection).
	timer:start(AUTOREPEAT_QUIET_MS, 0, schedule_resume)
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
	-- v:register defaults to '"' (the unnamed register). Only forward an
	-- explicit selection; otherwise prepending `"<reg>` corrupts the feed
	-- (e.g. `""ci"` derails the `ci"` operator through feedkeys).
	if state.register and state.register ~= "" and state.register ~= '"' then
		prefix = '"' .. state.register .. prefix
	end

	local termcoded = termcodes(prefix .. keys)
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

---@param mode string
---@param trigger string
---@param trigger_segs string[]
---@return boolean handled  -- true if held trigger was detected and fed
local function try_autorepeat_fast_path(mode, trigger, trigger_segs)
	if #trigger_segs ~= 1 then
		return false
	end
	local peek = vim.fn.getchar(1)
	if peek == 0 then
		return false
	end
	if index.key_label(getchar_to_str(peek)) ~= trigger_segs[1] then
		return false
	end
	suspend_trigger_for_autorepeat(mode, trigger)
	feed(trigger, "n")
	return true
end

---@return boolean over_limit  -- true if recursion limit hit and start() should bail
local function bump_recursion_guard()
	recursion_count = recursion_count + 1
	if recursion_count > 20 then
		vim.notify("[beast.key.hint] recursion limit hit; aborting", vim.log.levels.WARN)
		recursion_count = 0
		return true
	end
	if not recursion_timer then
		recursion_timer = assert((vim.uv or vim.loop).new_timer())
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
	return false
end

---Drain any keys already in the typeahead following a fast-typed trigger,
---walking the index. Returns a sequence to seed the hint with, or nil if the
---typed sequence was already fed through verbatim (caller should bail).
---@param mode string
---@param trigger string
---@param trigger_segs string[]
---@return string[]? pre_sequence
local function drain_typeahead_prefix(mode, trigger, trigger_segs)
	if vim.fn.getchar(1) == 0 then
		return {}
	end
	if not config.hint.auto_derive_subtriggers then
		-- Legacy bailout: defer to native resolver instead of opening the hint.
		feed(trigger, "in")
		return nil
	end

	local pre_sequence = {}
	while true do
		local c = vim.fn.getchar(0)
		if c == 0 then
			-- Typeahead drained, landed on a prefix node — open hint here.
			return pre_sequence
		end
		table.insert(pre_sequence, index.key_label(getchar_to_str(c)))

		local full = {}
		vim.list_extend(full, trigger_segs)
		vim.list_extend(full, pre_sequence)
		local node = index.walk(mode, full)
		-- No match or leaf reached: let Neovim resolve the full sequence.
		if not node or not next(node.children) then
			feed(trigger .. table.concat(pre_sequence, ""), "in")
			return nil
		end
	end
end

---@param mode string
---@param trigger string
---@param sequence string[]
---@param capture_count_register boolean
---@return Beast.Key.Hint.State
local function new_state(mode, trigger, sequence, capture_count_register)
	return {
		mode = mode,
		trigger = trigger,
		trigger_segs = index.split_keys(trigger),
		sequence = sequence,
		bufnr = vim.api.nvim_get_current_buf(),
		win_before = vim.api.nvim_get_current_win(),
		count = capture_count_register and vim.v.count or nil,
		register = capture_count_register and vim.v.register or nil,
	}
end

---Entry-point called by the trigger keymap.
---@param mode string
---@param trigger string
function M.start(mode, trigger)
	local trigger_segs = index.split_keys(trigger)

	-- Held trigger: delete the keymap so OS autorepeats run natively. Must
	-- run BEFORE the recursion guard since held keys easily exceed the limit.
	if try_autorepeat_fast_path(mode, trigger, trigger_segs) then
		return
	end

	if bump_recursion_guard() then
		return
	end

	-- Skip during macro recording or replay: feed the trigger verbatim so the
	-- macro records the literal keys (without opening our hint). 'in' inserts
	-- at the head; without 'i' the key reorders after pending chars and can
	-- corrupt operator+textobject sequences (e.g. ci").
	if vim.fn.reg_recording() ~= "" or vim.fn.reg_executing() ~= "" then
		feed(trigger, "in")
		return
	end

	local pre_sequence = drain_typeahead_prefix(mode, trigger, trigger_segs)
	if pre_sequence == nil then
		return
	end

	-- Visual selection is preserved across the hint: the floating window is
	-- non-focusable and opened with enter=false, so the cursor stays in the
	-- user's window and visual mode remains active while getcharstr blocks.
	local state = new_state(mode, trigger, pre_sequence, true)

	-- Run the modal loop under xpcall so any error still tears down the
	-- floating window cleanly and lets the trigger be re-registered.
	local ok, feed_or_err = xpcall(loop.run, debug.traceback, state)
	window.close(state)

	if not ok then
		vim.notify("[beast.key.hint] error: " .. tostring(feed_or_err), vim.log.levels.ERROR)
		return
	end

	if not feed_or_err or feed_or_err == "" then
		return
	end

	if feed_or_err == "\0autorepeat" then
		suspend_trigger_for_autorepeat(mode, trigger)
		-- Feed BOTH consumed presses: the one that fired this trigger callback
		-- and the one getcharstr ate inside loop.run. Feeding only one would
		-- drop a keypress per autorepeat cycle, halving the perceived rate.
		feed(trigger .. trigger, "n")
	else
		suspend_and_feed(state, feed_or_err)
	end
end

-- =============================================================================
-- Setup
-- =============================================================================

function M.setup()
	-- Invalidate index whenever managed keymaps change.
	local group = vim.api.nvim_create_augroup("BeastKeyHint", { clear = true })
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "BeastKeysChanged",
		callback = function()
			index.invalidate()
		end,
	})

	for _, trigger in ipairs(config.hint.triggers) do
		for _, mode in ipairs(config.hint.modes) do
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
	build_index = index.build_index,
	walk = index.walk,
	visible_children = index.visible_children,
	split_keys = index.split_keys,
	---Render the hint once at the given prefix (no getchar loop).
	---@param mode string
	---@param trigger string
	---@param sequence string[]
	render_once = function(mode, trigger, sequence)
		local state = new_state(mode, trigger, sequence or {}, false)
		loop.render(state)
		window.close(state)
	end,
	invalidate_cache = index.invalidate,
}

return M
