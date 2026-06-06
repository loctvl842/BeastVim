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
---@field view? Beast.View

---@type table<string, boolean>  -- "mode\0trigger" → registered
local registered = {}

-- Recursion guard: count successive start() invocations; reset by a timer.
local recursion_count = 0
local recursion_timer = nil

-- Autorepeat resume: when we delete a trigger keymap to let OS autorepeat
-- run natively, this timer re-registers it after a quiet period.
local AUTOREPEAT_QUIET_MS = 250
---@type table<string, uv.uv_timer_t>
local autorepeat_resume_timers = {}

---Delete the trigger keymap so subsequent OS-autorepeat presses execute
---natively (no Lua callback overhead). A uv timer re-registers it after
---AUTOREPEAT_QUIET_MS of inactivity — i.e. as soon as the user lets go.
---@param mode string
---@param trigger string
local function suspend_trigger_for_autorepeat(mode, trigger)
	local key = mode .. "\0" .. trigger
	if registered[key] then
		pcall(vim.keymap.del, mode, trigger)
		registered[key] = nil
	end
	local timer = autorepeat_resume_timers[key]
	if not timer then
		timer = assert((vim.uv or vim.loop).new_timer())
		autorepeat_resume_timers[key] = timer
	end
	timer:stop()
	timer:start(
		AUTOREPEAT_QUIET_MS,
		0,
		vim.schedule_wrap(function()
			autorepeat_resume_timers[key] = nil
			timer:close()
			M.register_trigger(mode, trigger)
		end)
	)
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
	local trigger_segs = index.split_keys(trigger)

	-- Autorepeat fast path: peek typeahead. If the next pending char equals
	-- the trigger root, the user is holding the trigger key. Delete the
	-- keymap so subsequent OS-autorepeats execute natively (no Lua callback
	-- overhead), and feed the current press noremap. Must run BEFORE the
	-- recursion guard since held keys easily exceed the limit.
	if #trigger_segs == 1 then
		local peek = vim.fn.getchar(1)
		if peek ~= 0 then
			local peek_raw = type(peek) == "number" and vim.fn.nr2char(peek) or peek
			if index.key_label(peek_raw) == trigger_segs[1] then
				suspend_trigger_for_autorepeat(mode, trigger)
				vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(trigger, true, true, true), "n", false)
				return
			end
		end
	end

	-- Recursion guard: if our trigger gets re-entered too many times in quick
	-- succession (e.g. user's keymap feeds <leader> recursively), bail out.
	recursion_count = recursion_count + 1
	if recursion_count > 20 then
		vim.notify("[beast.key.hint] recursion limit hit; aborting", vim.log.levels.WARN)
		recursion_count = 0
		return
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

	-- Skip during macro recording or replay: feed the trigger verbatim so the
	-- macro records the literal keys (without opening our hint).
	-- 'in' = insert at the head of the typeahead, no remap; without 'i' the
	-- key is appended, which reorders it after any pending characters and
	-- silently corrupts operator+textobject sequences (e.g. ci").
	if vim.fn.reg_recording() ~= "" or vim.fn.reg_executing() ~= "" then
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(trigger, true, true, true), "in", false)
		return
	end

	-- Fast-typed prefix handling.
	-- When the user types e.g. <leader>z faster than the trigger callback can
	-- fire, `z` is already in the typeahead by the time we get here. Drain
	-- it ourselves and walk the index so we can open the hint at the deepest
	-- matched subtree (e.g. directly at the <leader>z group) instead of
	-- bailing out and letting the keys resolve natively without ever
	-- surfacing the hint.
	local pre_sequence = {}
	if config.hint.auto_derive_subtriggers and vim.fn.getchar(1) ~= 0 then
		while true do
			local c = vim.fn.getchar(0)
			if c == 0 then
				break
			end
			local raw = type(c) == "number" and vim.fn.nr2char(c) or c
			local label = index.key_label(raw)
			table.insert(pre_sequence, label)

			local full = {}
			vim.list_extend(full, trigger_segs)
			vim.list_extend(full, pre_sequence)
			local node = index.walk(mode, full)
			-- No match, or leaf: feed everything verbatim and let Neovim
			-- resolve through the normal keymap chain.
			if not node or not next(node.children) then
				local feed = trigger .. table.concat(pre_sequence, "")
				vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(feed, true, true, true), "in", false)
				return
			end
			-- Still a prefix node — keep draining until either a leaf is
			-- reached or the typeahead is empty.
		end
		-- Fell through: typeahead drained, landed on a prefix node. Continue
		-- below with pre_sequence prefilled so the hint opens at that subtree.
	elseif vim.fn.getchar(1) ~= 0 then
		-- auto_derive_subtriggers disabled: preserve legacy bailout behavior.
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(trigger, true, true, true), "in", false)
		return
	end

	local state = {
		mode = mode,
		trigger = trigger,
		trigger_segs = trigger_segs,
		sequence = pre_sequence,
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
	local ok, feed = xpcall(loop.run, debug.traceback, state)
	window.close(state)

	if not ok then
		vim.notify("[beast.key.hint] error: " .. tostring(feed), vim.log.levels.ERROR)
		return
	end

	if feed and feed ~= "" then
		if feed == "\0autorepeat" then
			suspend_trigger_for_autorepeat(mode, trigger)
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(trigger, true, true, true), "n", false)
		else
			suspend_and_feed(state, feed)
		end
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
		local state = {
			mode = mode,
			trigger = trigger,
			trigger_segs = index.split_keys(trigger),
			sequence = sequence or {},
			bufnr = vim.api.nvim_get_current_buf(),
			win_before = vim.api.nvim_get_current_win(),
		}
		loop.render(state)
		window.close(state)
	end,
	invalidate_cache = index.invalidate,
}

return M
