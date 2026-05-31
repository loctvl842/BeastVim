-- Hunk preview float.
--
-- open_for_current_line() finds the hunk under the cursor and opens a
-- floating window showing the diff for that hunk: deleted lines in
-- BeastGitPreviewDelete, added lines in BeastGitPreviewAdd.
--
-- open_for_range(s, e) stitches every hunk overlapping the visual
-- selection [s, e] into a single float, separated by a thin divider.
--
-- Auto-closes on source-buffer CursorMoved / BufLeave / WinScrolled.
-- Inside the float, `q` and `<Esc>` close manually.

local api = vim.api
local View = require("beast.libs.view")

local M = {}

---@class Beast.Git.PreviewView : Beast.View
local PreviewView = View:extend()

---@type Beast.Git.PreviewView?
local current

-- =========================================================================
-- Hunk helpers
-- =========================================================================

---@param hunk Beast.Git.RawHunk
---@param cursor_line integer
---@return boolean
local function hunk_contains(hunk, cursor_line)
	if hunk.b_count == 0 then
		local anchor = hunk.b_start == 0 and 1 or hunk.b_start
		return cursor_line == anchor
	end
	return cursor_line >= hunk.b_start and cursor_line <= hunk.b_start + hunk.b_count - 1
end

---@param hunks Beast.Git.RawHunk[]
---@param cursor_line integer
---@return Beast.Git.RawHunk?
local function find_hunk(hunks, cursor_line)
	for _, h in ipairs(hunks) do
		if hunk_contains(h, cursor_line) then
			return h
		end
	end
end

---@param hunk Beast.Git.RawHunk
---@return integer first, integer last
local function hunk_b_span(hunk)
	if hunk.b_count == 0 then
		local anchor = hunk.b_start == 0 and 1 or hunk.b_start
		return anchor, anchor
	end
	return hunk.b_start, hunk.b_start + hunk.b_count - 1
end

---@param hunks Beast.Git.RawHunk[]
---@param range_start integer
---@param range_end integer
---@return Beast.Git.RawHunk[]
local function hunks_in_range(hunks, range_start, range_end)
	local out = {}
	for _, h in ipairs(hunks) do
		local first, last = hunk_b_span(h)
		if first <= range_end and last >= range_start then
			out[#out + 1] = h
		end
	end
	return out
end

---@param base string
---@param hunk Beast.Git.RawHunk
---@return string[]
local function slice_base(base, hunk)
	if hunk.a_count == 0 then
		return {}
	end
	local all = vim.split(base, "\n", { plain = true })
	local out = {}
	for i = hunk.a_start, hunk.a_start + hunk.a_count - 1 do
		out[#out + 1] = all[i] or ""
	end
	return out
end

---@param buf integer
---@param hunk Beast.Git.RawHunk
---@return string[]
local function slice_current(buf, hunk)
	if hunk.b_count == 0 then
		return {}
	end
	return api.nvim_buf_get_lines(buf, hunk.b_start - 1, hunk.b_start + hunk.b_count - 1, false)
end

-- =========================================================================
-- View helpers
-- =========================================================================

---@class Beast.Git.PreviewRow
---@field lnum integer? Source-buffer line number (nil for removed-only lines)
---@field marker string "- " | "+ " | "  "
---@field text string
---@field hl string?

---@param rows Beast.Git.PreviewRow[]
---@param buf integer
---@param from integer
---@param to integer
local function emit_context(rows, buf, from, to)
	if to < from then
		return
	end
	local lines = api.nvim_buf_get_lines(buf, from - 1, to, false)
	for i, l in ipairs(lines) do
		rows[#rows + 1] = { lnum = from + i - 1, marker = "  ", text = l }
	end
end

---@param hunk Beast.Git.RawHunk
---@return integer ctx_before_end, integer ctx_after_start
local function hunk_context_bounds(hunk)
	if hunk.b_count == 0 then
		-- Pure delete: removed lines sit between buf line b_start and b_start+1.
		-- topdelete (b_start=0): context before is empty, after starts at line 1.
		return hunk.b_start, hunk.b_start + 1
	end
	return hunk.b_start - 1, hunk.b_start + hunk.b_count
end

---@param buf integer
---@param st { base: string }
---@param hunks Beast.Git.RawHunk[]
---@param ctx_n integer
---@return Beast.Git.PreviewRow[]
local function build_rows(buf, st, hunks, ctx_n)
	local rows = {}
	local total = api.nvim_buf_line_count(buf)
	local prev_emit = 0

	for i, hunk in ipairs(hunks) do
		local before_end, after_start = hunk_context_bounds(hunk)

		-- Context before this hunk, clamped so we never re-emit a buf line.
		local before_start = math.max(prev_emit + 1, before_end - ctx_n + 1, 1)
		emit_context(rows, buf, before_start, before_end)
		if before_end >= before_start then
			prev_emit = before_end
		end

		-- Removed lines show the current-buffer line number where they would
		-- sit (b_start for change/delete; clamped to 1 for topdelete).
		local removed = slice_base(st.base, hunk)
		local removed_anchor = math.max(1, hunk.b_start)
		for j, l in ipairs(removed) do
			rows[#rows + 1] = {
				lnum = removed_anchor + j - 1,
				marker = "- ",
				text = l,
				hl = "BeastGitPreviewDelete",
			}
		end
		-- Added lines map to b_start .. b_start+b_count-1 in the current buffer.
		local added = slice_current(buf, hunk)
		for j, l in ipairs(added) do
			rows[#rows + 1] = {
				lnum = hunk.b_start + j - 1,
				marker = "+ ",
				text = l,
				hl = "BeastGitPreviewAdd",
			}
		end
		if hunk.b_count > 0 then
			prev_emit = hunk.b_start + hunk.b_count - 1
		end

		if i == #hunks then
			local after_end = math.min(total, after_start + ctx_n - 1)
			emit_context(rows, buf, after_start, after_end)
		end
	end

	return rows
end

---@param rows Beast.Git.PreviewRow[]
---@return string[] body, table<integer, string> hls, integer gutter_width
local function render_rows(rows)
	local max_lnum = 0
	for _, r in ipairs(rows) do
		if r.lnum and r.lnum > max_lnum then
			max_lnum = r.lnum
		end
	end
	local lnum_w = math.max(2, #tostring(max_lnum))

	local body, hls = {}, {}
	for i, r in ipairs(rows) do
		local lnum_str = r.lnum and tostring(r.lnum) or ""
		local gutter = string.rep(" ", lnum_w - #lnum_str) .. lnum_str .. " "
		body[i] = gutter .. r.marker .. r.text
		if r.hl then
			hls[i] = r.hl
		end
	end
	return body, hls, lnum_w + 1
end

---@param lines string[]
---@return integer
local function max_width(lines)
	local w = 1
	for _, l in ipairs(lines) do
		local lw = vim.fn.strdisplaywidth(l)
		if lw > w then
			w = lw
		end
	end
	return w
end

---@param body string[]
---@param hls table<integer, string>
---@param width integer
---@return integer buf, integer win
local function open_float(body, hls, width)
	local buf = api.nvim_create_buf(false, true)
	api.nvim_buf_set_lines(buf, 0, -1, false, body)
	vim.bo[buf].bufhidden = "wipe"

	local ns = api.nvim_create_namespace("beast_git_preview")
	for row, hl in pairs(hls) do
		api.nvim_buf_set_extmark(buf, ns, row - 1, 0, { line_hl_group = hl })
	end

	local height = math.min(#body, math.floor(vim.o.lines * 0.4))

	local win = api.nvim_open_win(buf, false, {
		relative = "cursor",
		row = 1,
		col = 0,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		focusable = true,
		noautocmd = true,
	})
	vim.api.nvim_set_option_value("winhighlight", "Normal:BeastGitPreviewNormal,FloatBorder:BeastGitPreviewBorder", { win = win })
	vim.api.nvim_set_option_value("wrap", false, { win = win })
	return buf, win
end

---@param buf integer  preview buffer
---@param source_buf integer  buffer whose cursor opened the preview
local function wire_close(buf, source_buf)
	vim.keymap.set("n", "q", M.close, { buffer = buf, nowait = true, silent = true })
	vim.keymap.set("n", "<Esc>", M.close, { buffer = buf, nowait = true, silent = true })

	local group = api.nvim_create_augroup("BeastGitPreview", { clear = true })
	api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave", "WinScrolled" }, {
		group = group,
		buffer = source_buf,
		once = true,
		callback = M.close,
	})
end

-- =========================================================================
-- Public API
-- =========================================================================

function M.close()
	if current then
		current:close()
		current = nil
	end
end

function M.open_for_current_line()
	if current and current.win and api.nvim_win_is_valid(current.win) then
		pcall(api.nvim_del_augroup_by_name, "BeastGitPreview")
		api.nvim_set_current_win(current.win)
		return
	end
	local cursor = api.nvim_win_get_cursor(0)[1]
	M.open_for_range(cursor, cursor)
end

---@param range_start integer
---@param range_end integer
function M.open_for_range(range_start, range_end)
	if current and current.win and api.nvim_win_is_valid(current.win) then
		pcall(api.nvim_del_augroup_by_name, "BeastGitPreview")
		api.nvim_set_current_win(current.win)
		return
	end
	if range_start > range_end then
		range_start, range_end = range_end, range_start
	end

	local git = require("beast.libs.git")
	local hunks = git.get_hunks()
	if #hunks == 0 then
		vim.notify("No hunks in this buffer", vim.log.levels.INFO, { title = "beast.git" })
		return
	end

	local source_buf = api.nvim_get_current_buf()
	local matched = hunks_in_range(hunks, range_start, range_end)
	if #matched == 0 then
		vim.notify("No hunk in selection", vim.log.levels.INFO, { title = "beast.git" })
		return
	end

	local st = git._get_state()
	if not st then
		return
	end

	local config = require("beast.libs.git.config")
	local ctx_n = config.preview and config.preview.context_size or 0

	local rows = build_rows(source_buf, st, matched, ctx_n)
	if #rows == 0 then
		return
	end
	local body, hls, gutter_w = render_rows(rows)

	local width = math.min(max_width(body) + 2, math.floor(vim.o.columns * 0.8))
	M.close()
	local buf, win = open_float(body, hls, width)
	-- Tint the gutter region so source line numbers read as LineNr.
	local ns_g = api.nvim_create_namespace("beast_git_preview_gutter")
	for i = 1, #body do
		api.nvim_buf_set_extmark(buf, ns_g, i - 1, 0, { end_col = gutter_w, hl_group = "LineNr" })
	end
	current = PreviewView(buf, win)
	wire_close(buf, source_buf)
end

-- Test-only seam — exposes pure helpers for unit tests.
M._test = { build_rows = build_rows, render_rows = render_rows }

return M
