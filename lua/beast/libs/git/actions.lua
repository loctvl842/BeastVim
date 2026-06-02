-- Stage / unstage / reset hunk actions.
--
-- All three are entry points called from keymaps; they coordinate
-- patch.lua (pure builder), apply.lua (async git apply), and the diff
-- pipeline in init.lua (post-apply refresh).
--
-- Toggle semantics for stage_hunk (matches gitsigns):
--   1. If there's an UNSTAGED hunk under the cursor → stage it.
--   2. Else if there's a STAGED hunk under the cursor → unstage it.
--   3. Else → no-op (notify "no hunk").
--
-- reset_hunk is buffer-local: it rewrites the buffer back to the index
-- version of the hunk's lines. No git command needed.

local api = vim.api

local apply_mod = require("beast.libs.git.apply")
local hunks_mod = require("beast.libs.git.hunks")
local patch = require("beast.libs.git.patch")
local repo = require("beast.libs.git.repo")

local M = {}

---@param msg string
---@param level integer
local function notify(msg, level)
	vim.notify("[beast.git] " .. msg, level)
end

--- Re-run the diff pipeline after a successful index mutation; the base text
--- changed so we need a fresh fetch.
---@param buf integer
local function refresh_base_after_apply(buf)
	-- Delegate via the public scheduler; avoids a circular require with init.lua.
	require("beast.libs.git").refresh(buf, { base = true, head = false })
end

--- Run an action that needs `path_data`. If `path_data` is nil the file is
--- untracked — we mark it intent-to-add, refresh path_data, then retry once.
---@param buf integer
---@param st Beast.Git.BufState
---@param run fun(st: Beast.Git.BufState)
local function with_path_data(buf, st, run)
	if st.path_data then
		return run(st)
	end
	repo.intent_to_add(st.ctx, function(ok, err)
		if not ok then
			notify("intent-to-add failed: " .. err, vim.log.levels.ERROR)
			return
		end
		repo.get_path_data(st.ctx, function(data)
			if not data then
				notify("path-data still missing after intent-to-add", vim.log.levels.ERROR)
				return
			end
			if not api.nvim_buf_is_valid(buf) then
				return
			end
			st.path_data = data
			-- base stays "" — intent-to-add writes the empty blob, so the
			-- index content didn't change. No need to refetch.
			run(st)
		end)
	end)
end

---@param text string
---@return string[]
local function split_lines(text)
	-- vim.split with plain=true is the documented way; trailing newline produces
	-- an empty entry we strip so line counts match nvim_buf_get_lines.
	local lines = vim.split(text, "\n", { plain = true })
	if lines[#lines] == "" then
		lines[#lines] = nil
	end
	return lines
end

---@param buf integer
---@return Beast.Git.BufState?
local function get_state(buf)
	return require("beast.libs.git")._get_state(buf)
end

-- =========================================================================
-- stage_hunk — toggle (unstaged → stage; staged → unstage)
-- =========================================================================

---@param buf integer?
---@param lnum integer?
function M.stage_hunk(buf, lnum)
	buf = buf or api.nvim_get_current_buf()
	lnum = lnum or api.nvim_win_get_cursor(0)[1]
	local st = get_state(buf)
	if not st then
		return notify("buffer not attached", vim.log.levels.WARN)
	end

	local unstaged_hunk = hunks_mod.find_at_buffer_line(st.hunks, lnum)
	if unstaged_hunk then
		return M._stage(buf, st, unstaged_hunk)
	end

	local staged_hunk = hunks_mod.find_staged_at_buffer_line(st.staged_hunks, st.hunks, lnum)
	if staged_hunk then
		return M._unstage(buf, st, staged_hunk)
	end

	notify("no hunk under cursor", vim.log.levels.INFO)
end

---@param buf integer?
---@param lnum integer?
function M.unstage_hunk(buf, lnum)
	buf = buf or api.nvim_get_current_buf()
	lnum = lnum or api.nvim_win_get_cursor(0)[1]
	local st = get_state(buf)
	if not st then
		return notify("buffer not attached", vim.log.levels.WARN)
	end
	local staged_hunk = hunks_mod.find_staged_at_buffer_line(st.staged_hunks, st.hunks, lnum)
	if not staged_hunk then
		return notify("no staged hunk under cursor", vim.log.levels.INFO)
	end
	M._unstage(buf, st, staged_hunk)
end

---@param buf integer
---@param st Beast.Git.BufState
---@param hunk Beast.Git.RawHunk Unstaged hunk (a_*=index, b_*=buffer)
function M._stage(buf, st, hunk)
	with_path_data(buf, st, function(state_with_pd)
		local buf_lines = api.nvim_buf_get_lines(buf, 0, -1, false)
		local ref_lines = split_lines(state_with_pd.base)
		local lines = patch.format(ref_lines, buf_lines, { hunk }, state_with_pd.path_data)
		apply_mod.apply(state_with_pd.ctx, lines, false, function(ok, err)
			if not ok then
				return notify("stage failed: " .. err, vim.log.levels.ERROR)
			end
			refresh_base_after_apply(buf)
		end)
	end)
end

---@param buf integer
---@param st Beast.Git.BufState
---@param hunk Beast.Git.RawHunk Staged hunk (a_*=HEAD, b_*=index)
function M._unstage(buf, st, hunk)
	with_path_data(buf, st, function(state_with_pd)
		local ref_lines = split_lines(state_with_pd.head)
		local target_lines = split_lines(state_with_pd.base)
		local lines = patch.format(ref_lines, target_lines, { hunk }, state_with_pd.path_data)
		apply_mod.apply(state_with_pd.ctx, lines, true, function(ok, err)
			if not ok then
				return notify("unstage failed: " .. err, vim.log.levels.ERROR)
			end
			refresh_base_after_apply(buf)
		end)
	end)
end

-- =========================================================================
-- reset_hunk — rewrite buffer lines from index
-- =========================================================================

---@param buf integer?
---@param lnum integer?
function M.reset_hunk(buf, lnum)
	buf = buf or api.nvim_get_current_buf()
	lnum = lnum or api.nvim_win_get_cursor(0)[1]
	local st = get_state(buf)
	if not st then
		return notify("buffer not attached", vim.log.levels.WARN)
	end
	local hunk = hunks_mod.find_at_buffer_line(st.hunks, lnum)
	if not hunk then
		return notify("no hunk under cursor", vim.log.levels.INFO)
	end

	local base_lines = split_lines(st.base)
	local replacement = {}
	for i = hunk.a_start, hunk.a_start + hunk.a_count - 1 do
		replacement[#replacement + 1] = base_lines[i] or ""
	end

	-- Buffer-edit range in 0-based exclusive form.
	local start_row, end_row
	if hunk.type == "add" then
		-- Pure add: delete the inserted buffer lines.
		start_row = hunk.b_start - 1
		end_row = hunk.b_start - 1 + hunk.b_count
	elseif hunk.type == "delete" then
		-- Pure delete: insert base lines back. b_start=0 means insert above line 1.
		start_row = hunk.b_start
		end_row = hunk.b_start
	else -- change
		start_row = hunk.b_start - 1
		end_row = hunk.b_start - 1 + hunk.b_count
	end

	api.nvim_buf_set_lines(buf, start_row, end_row, false, replacement)
end

return M
