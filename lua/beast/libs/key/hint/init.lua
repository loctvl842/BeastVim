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

	-- Skip when there is pending input queued (e.g. inside `:norm`, or our
	-- own suspend_and_feed re-entering after vim.schedule re-registered the
	-- trigger): replay the trigger AT THE HEAD so it lands before the
	-- already-queued operator argument.
	if vim.fn.getchar(1) ~= 0 then
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(trigger, true, true, true), "in", false)
		return
	end

	local state = {
		mode = mode,
		trigger = trigger,
		trigger_segs = index.split_keys(trigger),
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
	local ok, feed = xpcall(loop.run, debug.traceback, state)
	window.close(state)

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
