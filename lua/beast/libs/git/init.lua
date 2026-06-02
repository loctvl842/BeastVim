-- Public surface for beast.libs.git.
--
-- Lifecycle per buffer:
--   attach(buf) → resolve(repo) → bootstrap (base + head + path_data) →
--                 nvim_buf_attach (on_lines / on_reload / on_detach) → diff
-- Diff inputs:
--   base = `git show :file`     — index (the staging area)
--   head = `git show HEAD:file` — last commit
-- Diffs computed per recompute:
--   unstaged_hunks = diff(base, current_buffer)   — what you'd stage next
--   staged_hunks   = diff(head, base)             — what's staged, not committed
-- Re-diff triggers:
--   BufWritePost   — refetch base + recompute (covers hook-driven `git add`)
--   FocusGained    — refetch base + head (catches external stages / commits)
--   on_lines       — debounced (config.debounce_ms) recompute, base/head unchanged
--   on_reload      — buffer reloaded from disk (e.g. `:edit`), refetch base
-- Cleanup:
--   on_detach (buffer wiped / unloaded / reloaded) or M.detach(buf)
--
-- Single-flight per buffer: if a job is in-flight, a new request merges its
-- refresh flags into a pending bit-set; the in-flight job re-runs once on
-- completion if anything is pending.

local api = vim.api
local uv = vim.uv or vim.loop

local config = require("beast.libs.git.config")
local diff = require("beast.libs.git.diff")
local hunks_mod = require("beast.libs.git.hunks")
local repo = require("beast.libs.git.repo")
local signs = require("beast.libs.git.signs")

local M = {}

---@class Beast.Git.BufState
---@field ctx Beast.Git.RepoCtx
---@field path_data Beast.Git.PathData? Path metadata for patch headers (lazy)
---@field base string Cached index text (`git show :file`)
---@field head string Cached HEAD text (`git show HEAD:file`)
---@field hunks Beast.Git.RawHunk[] Unstaged hunks (base vs current buffer)
---@field staged_hunks Beast.Git.RawHunk[] Staged hunks (head vs base). b_* positions are in INDEX space, not buffer space — they only line up with the buffer when there are no unstaged edits above them.
---@field line_signs table<integer, { type: string }>
---@field staged_line_signs table<integer, { type: string }>
---@field timer uv.uv_timer_t? uv_timer_t for debounced on_lines recomputes
---@field running boolean Single-flight flag
---@field dirty { base: boolean, head: boolean }? Pending refresh flags requested while running
---@field last_diff_ms number? Wall-clock duration of the most recent recompute

---@type table<integer, Beast.Git.BufState>
local state = {}

---@type table<string, true>
local ft_ignore_set = {}
---@type table<string, true>
local bt_ignore_set = {}

local function rebuild_ignore_sets()
	ft_ignore_set = {}
	for _, ft in ipairs(config.ft_ignore or {}) do
		ft_ignore_set[ft] = true
	end
	bt_ignore_set = {}
	for _, bt in ipairs(config.bt_ignore or {}) do
		bt_ignore_set[bt] = true
	end
end

---@param buf integer
---@return boolean
local function buffer_eligible(buf)
	if not api.nvim_buf_is_valid(buf) then
		return false
	end
	local bo = vim.bo[buf]
	if bt_ignore_set[bo.buftype] then
		return false
	end
	if ft_ignore_set[bo.filetype] then
		return false
	end
	return true
end

-- =========================================================================
-- Diff pipeline
-- =========================================================================

---@param buf integer
---@param st Beast.Git.BufState
local function recompute(buf, st)
	if not api.nvim_buf_is_valid(buf) then
		return
	end
	local current_lines = api.nvim_buf_get_lines(buf, 0, -1, false)
	-- Append trailing newline to match `git show` output, otherwise a
	-- phantom EOF hunk appears on every diff.
	local current = table.concat(current_lines, "\n") .. "\n"
	local t0 = uv.hrtime()
	st.hunks = diff.compute_hunks(st.base, current)
	-- Staged diff is HEAD vs index. Inputs only change on commit (head) or
	-- stage (base), but we recompute here for simplicity. vim.text.diff
	-- short-circuits when inputs are unchanged, so the cost is small.
	-- If profiles show this dominating, gate behind a "ref changed" flag.
	st.staged_hunks = diff.compute_hunks(st.head, st.base)
	st.line_signs = hunks_mod.expand_signs(st.hunks, #current_lines)
	st.staged_line_signs = hunks_mod.expand_staged_signs(st.staged_hunks, st.hunks, #current_lines)
	signs.place_unstaged(buf, st.line_signs)
	signs.place_staged(buf, st.staged_line_signs)
	st.last_diff_ms = (uv.hrtime() - t0) / 1e6
end

---@param buf integer
---@param refresh_base boolean Refetch index text before recompute
---@param refresh_head boolean Refetch HEAD text before recompute
local function schedule_diff(buf, refresh_base, refresh_head)
	local st = state[buf]
	if not st then
		return
	end
	if st.running then
		st.dirty = st.dirty or { base = false, head = false }
		st.dirty.base = st.dirty.base or refresh_base
		st.dirty.head = st.dirty.head or refresh_head
		return
	end
	st.running = true

	local function finish()
		st.running = false
		local d = st.dirty
		if d then
			st.dirty = nil
			schedule_diff(buf, d.base, d.head)
		end
	end

	local pending = 0
	local function maybe_run()
		if pending > 0 then
			return
		end
		recompute(buf, st)
		finish()
	end

	if refresh_base then
		pending = pending + 1
		repo.get_base(st.ctx, function(text)
			if not state[buf] then
				return
			end
			st.base = text
			pending = pending - 1
			maybe_run()
		end)
	end
	if refresh_head then
		pending = pending + 1
		repo.get_head(st.ctx, function(text)
			if not state[buf] then
				return
			end
			st.head = text
			pending = pending - 1
			maybe_run()
		end)
	end
	if pending == 0 then
		recompute(buf, st)
		finish()
	end
end

-- =========================================================================
-- Attach / detach
-- =========================================================================

---@param buf integer
---@param session table The state table we were attached against
local function on_lines_change(buf, session)
	local st = state[buf]
	-- Self-prune if the buffer was detached, or if a fresh attach swapped
	-- in a new session (the new subscription handles future events).
	if not st or st ~= session then
		return true -- detach
	end
	if st.timer then
		st.timer:stop()
	else
		st.timer = assert(uv.new_timer(), "failed to create timer")
	end
	st.timer:start(
		config.debounce_ms,
		0,
		vim.schedule_wrap(function()
			schedule_diff(buf, false, false)
		end)
	)
end

-- Initial fetch of base + head + path_data. Path data failure is non-fatal:
-- staging actions in Phase 3 will retry the lookup (covers files added to the
-- index after attach).
---@param buf integer
---@param ctx Beast.Git.RepoCtx
---@param done fun()
local function bootstrap_state(buf, ctx, done)
	local base, head, path_data = "", "", nil
	local pending = 0

	local function maybe_done()
		if pending > 0 then
			return
		end
		if not api.nvim_buf_is_valid(buf) then
			return
		end
		state[buf] = {
			ctx = ctx,
			path_data = path_data,
			base = base,
			head = head,
			hunks = {},
			staged_hunks = {},
			line_signs = {},
			staged_line_signs = {},
			timer = nil,
			running = false,
			dirty = nil,
		}
		done()
	end

	pending = pending + 1
	repo.get_base(ctx, function(text)
		base = text
		pending = pending - 1
		maybe_done()
	end)
	pending = pending + 1
	repo.get_head(ctx, function(text)
		head = text
		pending = pending - 1
		maybe_done()
	end)
	pending = pending + 1
	repo.get_path_data(ctx, function(data)
		path_data = data
		pending = pending - 1
		maybe_done()
	end)
end

-- Buffers with an attach in flight (repo.resolve / bootstrap_state pending).
-- Guards against parallel bootstraps if M.attach is called twice on the same
-- buf before the first finishes (e.g. BufReadPost firing during BufFilePost's
-- scheduled re-attach).
---@type table<integer, boolean>
local attaching = {}

---@param buf integer
local function abort_attach(buf)
	attaching[buf] = nil
	repo.invalidate(buf)
end

---@param buf integer?
function M.attach(buf)
	buf = buf or api.nvim_get_current_buf()
	if state[buf] or attaching[buf] or not buffer_eligible(buf) then
		return
	end
	attaching[buf] = true
	repo.resolve(buf, function(ctx)
		if not ctx or not api.nvim_buf_is_valid(buf) then
			abort_attach(buf)
			return
		end
		bootstrap_state(buf, ctx, function()
			attaching[buf] = nil
			-- Capture the attach session (the state-table identity). Any
			-- callback closed over `session` will no-op if the buffer has
			-- been re-attached in the meantime (state[buf] points to a
			-- different table) — closes the double-subscription window
			-- created by :edit firing on_detach + BufReadPost reattach.
			local session = state[buf]
			-- on_lines runs in a fast event for every line change
			-- (including programmatic edits that TextChanged/I would
			-- miss), so the handler only schedules work via a uv timer.
			local ok = api.nvim_buf_attach(buf, false, {
				on_lines = function(_, b)
					return on_lines_change(b, session)
				end,
				on_reload = function(_, b)
					if state[b] == session then
						vim.schedule(function()
							schedule_diff(b, true, false)
						end)
					end
				end,
				on_detach = function(_, b)
					vim.schedule(function()
						if state[b] == session then
							M.detach(b)
						end
					end)
				end,
			})
			if not ok then
				M.detach(buf)
				return
			end
			schedule_diff(buf, false, false)
		end)
	end)
end

---@param buf integer?
function M.detach(buf)
	buf = buf or api.nvim_get_current_buf()
	attaching[buf] = nil
	local st = state[buf]
	if not st then
		return
	end
	if st.timer then
		st.timer:stop()
		st.timer:close()
	end
	state[buf] = nil
	repo.invalidate(buf)
	signs.clear(buf)
end

-- =========================================================================
-- Inspection (Phase 2 / 3 consumers)
-- =========================================================================

---@param buf integer?
---@return Beast.Git.RawHunk[]
function M.get_hunks(buf)
	buf = buf or api.nvim_get_current_buf()
	local st = state[buf]
	return st and st.hunks or {}
end

--- Hunks representing changes already staged in the index (HEAD vs index).
--- Note: b_* positions are in INDEX line space — only aligned with the buffer
--- when there are no unstaged edits above them.
---@param buf integer?
---@return Beast.Git.RawHunk[]
function M.get_staged_hunks(buf)
	buf = buf or api.nvim_get_current_buf()
	local st = state[buf]
	return st and st.staged_hunks or {}
end

---@param buf integer?
---@return Beast.Git.BufState?
function M._get_state(buf)
	buf = buf or api.nvim_get_current_buf()
	return state[buf]
end

---@param direction "next" | "prev"
---@param opts? Beast.Git.NavOpts
function M.nav_hunk(direction, opts)
	require("beast.libs.git.nav").nav_hunk(direction, opts)
end

---@param opts? Beast.Git.NavOpts
function M.next_hunk(opts)
	require("beast.libs.git.nav").nav_hunk("next", opts or { wrap = true })
end

---@param opts? Beast.Git.NavOpts
function M.prev_hunk(opts)
	require("beast.libs.git.nav").nav_hunk("prev", opts or { wrap = true })
end

function M.preview_hunk()
	local vs, ve = require("beast.libs.git.visual").range()
	if vs then
		return require("beast.libs.git.preview").open_for_range(vs, ve)
	end
	require("beast.libs.git.preview").open_for_current_line()
end

---@param range_start integer
---@param range_end integer
function M.preview_hunk_range(range_start, range_end)
	require("beast.libs.git.preview").open_for_range(range_start, range_end)
end

-- =========================================================================
-- Hunk actions (Phase 3) — wrapped with the dot-repeat shim from Phase 4
-- =========================================================================

---@type fun()?
local last_repeatable_action = nil

--- Replay the most recent stage/reset action (any line). Bind to `.` via
--- `:lua vim.go.operatorfunc = ...` or call directly from a keymap.
function M.repeat_action()
	if last_repeatable_action then
		last_repeatable_action()
	end
end

--- Memoise the call site so M.repeat_action can replay it. Captures the
--- args resolved at call time (current buffer + cursor line), so `.` after
--- moving the cursor still applies the action to wherever the cursor went
--- — same UX as gitsigns' default repeat shim.
---@generic T
---@param fn fun(buf: integer?, lnum: integer?)
---@return fun(buf: integer?, lnum: integer?)
local function wrap_repeatable(fn)
	return function(buf, lnum)
		last_repeatable_action = function()
			fn(nil, nil)
		end
		fn(buf, lnum)
	end
end

---@param buf integer?
---@param lnum integer? 1-based buffer line (default: current cursor line)
M.stage_hunk = wrap_repeatable(function(buf, lnum)
	require("beast.libs.git.actions").stage_hunk(buf, lnum)
end)

---@param buf integer?
---@param lnum integer?
M.unstage_hunk = wrap_repeatable(function(buf, lnum)
	require("beast.libs.git.actions").unstage_hunk(buf, lnum)
end)

---@param buf integer?
---@param lnum integer?
M.reset_hunk = wrap_repeatable(function(buf, lnum)
	require("beast.libs.git.actions").reset_hunk(buf, lnum)
end)

--- Stage every unstaged hunk whose buffer footprint intersects `[s, e]`.
--- Whole-hunk inclusion (gitsigns/mini.diff parity). Intended for visual
--- range mappings — see init.lua for the `<leader>gs` example.
---@param buf integer?
---@param s integer 1-based start line (inclusive)
---@param e integer 1-based end line (inclusive)
function M.stage_hunk_range(buf, s, e)
	require("beast.libs.git.actions").stage_hunk_range(buf, s, e)
end

---@param buf integer?
---@param s integer
---@param e integer
function M.reset_hunk_range(buf, s, e)
	require("beast.libs.git.actions").reset_hunk_range(buf, s, e)
end

--- Trigger a re-diff for `buf`. Actions call this after mutating the index
--- so the gutter reflects the new state without waiting for the next
--- on_lines event.
---@param buf integer?
---@param opts? { base?: boolean, head?: boolean }
function M.refresh(buf, opts)
	buf = buf or api.nvim_get_current_buf()
	opts = opts or {}
	schedule_diff(buf, opts.base ~= false, opts.head == true)
end

M._namespaces = signs.namespaces

-- =========================================================================
-- Event wiring
-- =========================================================================
--
-- Per-buffer text mutations are caught by `nvim_buf_attach.on_lines` (set up
-- in `M.attach`). The autocmds below only cover events that aren't part of the
-- buffer-subscription protocol: initial attach, save, focus, rename.

local function ensure_autocmds()
	local group = api.nvim_create_augroup("BeastGit", { clear = true })

	api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
		group = group,
		callback = function(ev)
			-- `:edit` on an already-attached buffer reloads its contents
			-- and severs the nvim_buf_attach subscription. Detach our
			-- stale state first so M.attach below sets up a fresh session
			-- (and a fresh on_lines subscription).
			if state[ev.buf] then
				M.detach(ev.buf)
			end
			M.attach(ev.buf)
		end,
	})
	api.nvim_create_autocmd("BufWritePost", {
		group = group,
		callback = function(ev)
			if state[ev.buf] then
				-- Save updates the working tree, not the index. Refetch base
				-- defensively in case the user has a pre/post-write hook that
				-- stages the file (e.g. format-on-save → git add).
				schedule_diff(ev.buf, true, false)
			end
		end,
	})
	api.nvim_create_autocmd("FocusGained", {
		group = group,
		callback = function()
			for buf, _ in pairs(state) do
				if api.nvim_buf_is_valid(buf) then
					-- External terminal might have committed (HEAD) or
					-- staged (index) since we last looked.
					schedule_diff(buf, true, true)
				end
			end
		end,
	})
	api.nvim_create_autocmd("BufFilePost", {
		group = group,
		callback = function(ev)
			M.detach(ev.buf)
			vim.schedule(function()
				M.attach(ev.buf)
			end)
		end,
	})
end

---@param opts? Beast.Git.Config
function M.setup(opts)
	config.setup(opts)
	require("beast.libs.git.highlights")
	rebuild_ignore_sets()
	ensure_autocmds()
	-- Attach existing loaded buffers (lazy-load case).
	for _, buf in ipairs(api.nvim_list_bufs()) do
		if api.nvim_buf_is_loaded(buf) then
			M.attach(buf)
		end
	end
end

return M
