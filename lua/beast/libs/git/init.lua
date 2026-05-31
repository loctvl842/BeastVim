-- Public surface for beast.libs.git.
--
-- Lifecycle per buffer:
--   attach(buf) → resolve(repo) → get_base → diff → expand → place extmarks
-- Re-diff triggers:
--   BufWritePost   — refetch base + recompute
--   FocusGained    — refetch base for every attached buffer (catches external commits)
--   TextChanged/I  — debounced (config.debounce_ms) recompute, base unchanged
-- Cleanup:
--   BufDelete / BufWipeout / detach(buf)
--
-- Single-flight per buffer: if a job is in-flight, a new request flips the
-- `dirty` bit; the in-flight job re-runs once on completion if dirty.

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
---@field base string Cached HEAD text
---@field hunks Beast.Git.RawHunk[] Latest computed hunks
---@field line_signs table<integer, { type: string }>
---@field timer userdata? uv_timer_t for debounced TextChanged
---@field running boolean Single-flight flag
---@field dirty boolean Re-run requested while running
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
	local current = table.concat(current_lines, "\n")
	local t0 = uv.hrtime()
	st.hunks = diff.compute_hunks(st.base, current)
	st.line_signs = hunks_mod.expand_signs(st.hunks, #current_lines)
	signs.place(buf, st.line_signs)
	st.last_diff_ms = (uv.hrtime() - t0) / 1e6
end

---@param buf integer
---@param refresh_base boolean
local function schedule_diff(buf, refresh_base)
	local st = state[buf]
	if not st then
		return
	end
	if st.running then
		st.dirty = true
		return
	end
	st.running = true

	local function finish()
		st.running = false
		if st.dirty then
			st.dirty = false
			schedule_diff(buf, false)
		end
	end

	if refresh_base then
		repo.get_base(st.ctx, function(text)
			if not state[buf] then
				return
			end
			st.base = text
			recompute(buf, st)
			finish()
		end)
	else
		recompute(buf, st)
		finish()
	end
end

-- =========================================================================
-- Attach / detach
-- =========================================================================

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
		repo.get_base(ctx, function(base)
			if not api.nvim_buf_is_valid(buf) then
				return
			end
			state[buf] = {
				ctx = ctx,
				base = base,
				hunks = {},
				line_signs = {},
				timer = nil,
				running = false,
				dirty = false,
			}
			schedule_diff(buf, false)
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

---@param buf integer?
---@return Beast.Git.BufState?
function M._get_state(buf)
	buf = buf or api.nvim_get_current_buf()
	return state[buf]
end

M._namespace = signs.namespace

-- =========================================================================
-- Event wiring
-- =========================================================================

---@param buf integer
local function on_text_changed(buf)
	local st = state[buf]
	if not st then
		return
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
			schedule_diff(buf, false)
		end)
	)
end

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
				schedule_diff(ev.buf, true)
			end
		end,
	})
	api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = group,
		callback = function(ev)
			if state[ev.buf] then
				on_text_changed(ev.buf)
			end
		end,
	})
	api.nvim_create_autocmd("FocusGained", {
		group = group,
		callback = function()
			for buf, _ in pairs(state) do
				if api.nvim_buf_is_valid(buf) then
					schedule_diff(buf, true)
				end
			end
		end,
	})
	api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
		group = group,
		callback = function(ev)
			M.detach(ev.buf)
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
	rebuild_ignore_sets()
	signs.set_icons(config.icons)
	ensure_autocmds()
	-- Attach existing loaded buffers (lazy-load case).
	for _, buf in ipairs(api.nvim_list_bufs()) do
		if api.nvim_buf_is_loaded(buf) then
			M.attach(buf)
		end
	end
end

return M
