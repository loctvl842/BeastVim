-- Hunk preview float.
--
-- open_for_current_line() finds the hunk under the cursor and opens a
-- floating window showing the diff: deleted lines in BeastGitPreviewDelete,
-- added lines in BeastGitPreviewAdd.
--
-- open_for_range(s, e) stitches every hunk overlapping [s, e] (plus any
-- neighbouring hunks within preview.adjacent_gap unchanged lines) into a
-- single unified timeline.
--
-- Auto-closes on source-buffer CursorMoved (off hunk lines), BufLeave,
-- and when the hunk scrolls fully off-screen. Inside the float, `q` and
-- `<Esc>` close manually.

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

---Expand `seed` to include neighbouring hunks whose gap (unchanged lines
---between them) is ≤ adj_gap.
---@param hunks Beast.Git.RawHunk[]  ordered by b_start
---@param seed Beast.Git.RawHunk[]   contiguous slice already picked
---@param adj_gap integer  max unchanged lines between hunks for auto-merge (0 = touching)
---@return Beast.Git.RawHunk[]
local function expand_adjacent(hunks, seed, adj_gap)
	if #seed == 0 then
		return seed
	end
	local index_of = {}
	for i, h in ipairs(hunks) do
		index_of[h] = i
	end
	local lo = index_of[seed[1]]
	local hi = index_of[seed[#seed]]
	local gap_threshold = math.max(0, adj_gap or 0) + 1

	while lo > 1 do
		local _, prev_last = hunk_b_span(hunks[lo - 1])
		local curr_first = hunk_b_span(hunks[lo])
		if curr_first - prev_last - 1 >= gap_threshold then
			break
		end
		lo = lo - 1
	end
	while hi < #hunks do
		local _, curr_last = hunk_b_span(hunks[hi])
		local next_first = hunk_b_span(hunks[hi + 1])
		if next_first - curr_last - 1 >= gap_threshold then
			break
		end
		hi = hi + 1
	end

	local out = {}
	for i = lo, hi do
		out[#out + 1] = hunks[i]
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

	-- Trim leading + trailing blank context rows so the float doesn't show
	-- empty source lines at its edges (they add no signal).
	while #rows > 0 and rows[#rows].marker == "  " and rows[#rows].text == "" do
		rows[#rows] = nil
	end
	while #rows > 0 and rows[1].marker == "  " and rows[1].text == "" do
		table.remove(rows, 1)
	end

	return rows
end

---@class Beast.Git.PreviewGutter
---@field lnum_text string  Padded line-number string + trailing space
---@field lnum_hl string    Highlight group for the line number
---@field marker string     "- " | "+ " | "  "
---@field marker_hl string  Highlight group for the marker (and line bg)

---@param rows Beast.Git.PreviewRow[]
---@return string[] body  pure code lines (no gutter), one per row
---@return table<integer, string> hls  row → line_hl_group
---@return Beast.Git.PreviewGutter[] gutters  one per row
---@return integer gutter_width  display width of the prefix column
local function render_rows(rows)
	local max_lnum = 0
	for _, r in ipairs(rows) do
		if r.lnum and r.lnum > max_lnum then
			max_lnum = r.lnum
		end
	end
	local lnum_w = math.max(2, #tostring(max_lnum))

	local body, hls, gutters = {}, {}, {}
	for i, r in ipairs(rows) do
		local lnum_str = r.lnum and tostring(r.lnum) or ""
		local lnum_text = string.rep(" ", lnum_w - #lnum_str) .. lnum_str .. " "
		local marker_hl
		if r.marker == "- " then
			marker_hl = "BeastGitPreviewDeleteSign"
		elseif r.marker == "+ " then
			marker_hl = "BeastGitPreviewAddSign"
		else
			marker_hl = "LineNr"
		end
		gutters[i] = {
			lnum_text = lnum_text,
			lnum_hl = marker_hl,
			marker = r.marker,
			marker_hl = marker_hl,
		}
		body[i] = r.text
		if r.hl then
			hls[i] = r.hl
		end
	end
	return body, hls, gutters, lnum_w + 1 + 2
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

---@param buf integer
---@param source_ft string
local function maybe_start_treesitter(buf, source_ft)
	if not source_ft or source_ft == "" then
		return
	end
	vim.bo[buf].filetype = source_ft
	local lang = vim.treesitter.language.get_lang(source_ft) or source_ft
	pcall(vim.treesitter.start, buf, lang)
end

---@param buf integer
---@param body string[]
---@param hls table<integer, string>
---@param gutters Beast.Git.PreviewGutter[]
local function apply_decorations(buf, body, hls, gutters)
	local ns = api.nvim_create_namespace("beast_git_preview")
	for i = 1, #body do
		local g = gutters[i]
		api.nvim_buf_set_extmark(buf, ns, i - 1, 0, {
			virt_text = { { g.lnum_text, g.lnum_hl }, { g.marker, g.marker_hl } },
			virt_text_pos = "inline",
		})
		if hls[i] then
			api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { line_hl_group = hls[i] })
		end
	end
end

---@return integer
local function resolve_max_height()
	local cfg = (require("beast.libs.git.config").preview or {}).max_height or 0.4
	if cfg > 0 and cfg < 1 then
		return math.floor(vim.o.lines * cfg)
	end
	return math.floor(cfg)
end

---@param body string[]
---@param hls table<integer, string>
---@param gutters Beast.Git.PreviewGutter[]
---@param width integer
---@param source_ft string
---@param source_win integer
---@param anchor_lnum integer  1-indexed buffer line to anchor the float below
---@return integer buf, integer win
local function open_float(body, hls, gutters, width, source_ft, source_win, anchor_lnum)
	local buf = Buffer.new("")
	api.nvim_buf_set_lines(buf, 0, -1, false, body)
	vim.bo[buf].modifiable = false
	vim.bo[buf].readonly = true

	maybe_start_treesitter(buf, source_ft)
	apply_decorations(buf, body, hls, gutters)

	local height = math.min(#body, math.max(1, resolve_max_height()))
	local win = api.nvim_open_win(buf, false, {
		relative = "win",
		win = source_win,
		bufpos = { anchor_lnum - 1, 0 },
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
---@param source_win integer
---@param hunk_lines table<integer, boolean>  set of buffer lines covered by matched hunks
---@param hunk_min integer  smallest line covered by matched hunks
---@param hunk_max integer  largest line covered by matched hunks
local function wire_close(buf, source_buf, source_win, hunk_lines, hunk_min, hunk_max)
	vim.keymap.set("n", "q", M.close, { buffer = buf, nowait = true, silent = true })
	vim.keymap.set("n", "<Esc>", M.close, { buffer = buf, nowait = true, silent = true })

	local group = api.nvim_create_augroup("BeastGitPreview", { clear = true })
	api.nvim_create_autocmd("BufLeave", {
		group = group,
		buffer = source_buf,
		callback = function()
			vim.schedule(function()
				if current and current.win and api.nvim_get_current_win() == current.win then
					return
				end
				M.close()
			end)
		end,
	})
	api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
		group = group,
		buffer = source_buf,
		callback = function()
			local lnum = api.nvim_win_get_cursor(source_win)[1]
			if not hunk_lines[lnum] then
				M.close()
			end
		end,
	})
	-- Re-anchor float on scroll; close only when whole hunk range is off-screen.
	api.nvim_create_autocmd("WinScrolled", {
		group = group,
		callback = function()
			if not (current and current.win and api.nvim_win_is_valid(current.win)) then
				return
			end
			if not api.nvim_win_is_valid(source_win) then
				return
			end
			local top = vim.fn.line("w0", source_win)
			local bot = vim.fn.line("w$", source_win)
			if hunk_max < top or hunk_min > bot then
				M.close()
				return
			end
			local visible = math.min(math.max(hunk_min, top), hunk_max, bot)
			pcall(api.nvim_win_set_config, current.win, {
				relative = "win",
				win = source_win,
				bufpos = { visible - 1, 0 },
				row = 1,
				col = 0,
			})
		end,
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

---@return boolean focused  true if an existing float was focused
local function focus_if_open()
	if current and current.win and api.nvim_win_is_valid(current.win) then
		pcall(api.nvim_del_augroup_by_name, "BeastGitPreview")
		api.nvim_set_current_win(current.win)
		return true
	end
	return false
end

---@param matched Beast.Git.RawHunk[]
---@return table<integer, boolean> hunk_lines, integer hunk_min, integer hunk_max
local function compute_hunk_extent(matched)
	local hunk_lines = {}
	local hunk_min, hunk_max = math.huge, -math.huge
	for _, h in ipairs(matched) do
		local s = math.max(1, h.b_start or 1)
		local n = math.max(h.b_count or 0, 1)
		for l = s, s + n - 1 do
			hunk_lines[l] = true
			if l < hunk_min then
				hunk_min = l
			end
			if l > hunk_max then
				hunk_max = l
			end
		end
	end
	return hunk_lines, hunk_min, hunk_max
end

---@param mode string?  "full" | "fit"
---@param body string[]
---@param gutter_w integer
---@return integer
local function compute_width(mode, body, gutter_w)
	if mode == "fit" then
		return math.min(max_width(body) + gutter_w + 2, math.floor(vim.o.columns * 0.8))
	end
	return math.max(1, vim.o.columns - 2)
end

function M.open_for_current_line()
	if focus_if_open() then
		return
	end
	local cursor = api.nvim_win_get_cursor(0)[1]
	M.open_for_range(cursor, cursor)
end

---@param range_start integer
---@param range_end integer
function M.open_for_range(range_start, range_end)
	if focus_if_open() then
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
	local preview_cfg = config.preview or {}
	local ctx_n = preview_cfg.context_size or 0
	-- Auto-cluster adjacent hunks so back-to-back changes preview together.
	matched = expand_adjacent(hunks, matched, preview_cfg.adjacent_gap or 0)

	local rows = build_rows(source_buf, st, matched, ctx_n)
	if #rows == 0 then
		return
	end
	local body, hls, gutters, gutter_w = render_rows(rows)

	local source_ft = vim.bo[source_buf].filetype
	local source_win = api.nvim_get_current_win()
	local hunk_lines, hunk_min, hunk_max = compute_hunk_extent(matched)
	local width = compute_width(preview_cfg.width, body, gutter_w)

	M.close()
	local buf, win = open_float(body, hls, gutters, width, source_ft, source_win, hunk_min)
	current = PreviewView(buf, win)
	wire_close(buf, source_buf, source_win, hunk_lines, hunk_min, hunk_max)
end

-- Test-only seam — exposes pure helpers for unit tests.
M._test = { build_rows = build_rows, render_rows = render_rows, expand_adjacent = expand_adjacent }

return M
