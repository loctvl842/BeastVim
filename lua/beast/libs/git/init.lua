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
	signs.place(buf, st.line_signs)
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
local function on_lines_change(buf)
	local st = state[buf]
	if not st then
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
	local pending = 3
	local base, head, path_data = "", "", nil

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
			timer = nil,
			running = false,
			dirty = nil,
		}
		done()
	end

	repo.get_base(ctx, function(text)
		base = text
		pending = pending - 1
		maybe_done()
	end)
	repo.get_head(ctx, function(text)
		head = text
		pending = pending - 1
		maybe_done()
	end)
	repo.get_path_data(ctx, function(data)
		path_data = data
		pending = pending - 1
		maybe_done()
	end)
end

---@param buf integer?
function M.attach(buf)
	buf = buf or api.nvim_get_current_buf()
	if state[buf] or not buffer_eligible(buf) then
		return
	end
	repo.resolve(buf, function(ctx)
		if not ctx or not api.nvim_buf_is_valid(buf) then
			return
		end
		bootstrap_state(buf, ctx, function()
			-- Subscribe to buffer mutations. on_lines fires synchronously in a
			-- fast event for every line change (including programmatic edits
			-- that TextChanged/I would miss), so the handler only schedules
			-- work via a uv timer.
			local ok = api.nvim_buf_attach(buf, false, {
				on_lines = function(_, b)
					return on_lines_change(b)
				end,
				on_reload = function(_, b)
					if state[b] then
						vim.schedule(function()
							schedule_diff(b, true, false)
						end)
					end
				end,
				on_detach = function(_, b)
					vim.schedule(function()
						M.detach(b)
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
	require("beast.libs.git.preview").open_for_current_line()
end

---@param range_start integer
---@param range_end integer
function M.preview_hunk_range(range_start, range_end)
	require("beast.libs.git.preview").open_for_range(range_start, range_end)
end

M._namespace = signs.namespace

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
