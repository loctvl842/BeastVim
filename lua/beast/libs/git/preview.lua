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

---@class Beast.Git.PreviewView : Beast.View.Instance
---@overload fun(buf?: integer, win?: integer): Beast.Git.PreviewView
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

---@param text string
---@param start integer 1-based start line (inclusive)
---@param count integer number of lines (0 = empty result)
---@return string[]
local function slice_text(text, start, count)
	if count == 0 then
		return {}
	end
	local all = vim.split(text, "\n", { plain = true })
	local out = {}
	for i = start, start + count - 1 do
		out[#out + 1] = all[i] or ""
	end
	return out
end

-- =========================================================================
-- Source abstraction
-- =========================================================================
-- Preview reads from two places depending on which tier is being shown:
--   - unstaged tier → "+ " / context come from the live buffer
--   - staged tier   → "+ " / context come from the INDEX text (st.base)
--
-- Source.get_lines(from, to)  1-based, inclusive on both ends → string[]
-- Source.line_count()         total line count (used to clamp tail context)

---@class Beast.Git.PreviewSource
---@field get_lines fun(from: integer, to: integer): string[]
---@field line_count fun(): integer

---@param buf integer
---@return Beast.Git.PreviewSource
local function buffer_source(buf)
	return {
		get_lines = function(from, to)
			if to < from then
				return {}
			end
			return api.nvim_buf_get_lines(buf, from - 1, to, false)
		end,
		line_count = function()
			return api.nvim_buf_line_count(buf)
		end,
	}
end

---@param text string
---@return Beast.Git.PreviewSource
local function string_source(text)
	-- Trailing newline from `git show` produces a phantom empty line —
	-- drop it so the index source matches its actual line count.
	local lines = vim.split(text, "\n", { plain = true })
	if #lines > 0 and lines[#lines] == "" then
		lines[#lines] = nil
	end
	return {
		get_lines = function(from, to)
			local out = {}
			for i = from, to do
				out[#out + 1] = lines[i] or ""
			end
			return out
		end,
		line_count = function()
			return #lines
		end,
	}
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
---@param source Beast.Git.PreviewSource
---@param from integer
---@param to integer
local function emit_context(rows, source, from, to)
	if to < from then
		return
	end
	local lines = source.get_lines(from, to)
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

---@param source Beast.Git.PreviewSource
---@param removed_text string  Full text of the "before" side (base for unstaged, head for staged)
---@param added_text string?   Full text of the "after" side; nil = read added/context from `source` (unstaged case)
---@param hunks Beast.Git.RawHunk[]
---@param ctx_n integer
---@return Beast.Git.PreviewRow[]
local function build_rows(source, removed_text, added_text, hunks, ctx_n)
	local rows = {}
	local total = source.line_count()
	local prev_emit = 0

	for i, hunk in ipairs(hunks) do
		local before_end, after_start = hunk_context_bounds(hunk)

		-- Context before this hunk, clamped so we never re-emit a buf line.
		local before_start = math.max(prev_emit + 1, before_end - ctx_n + 1, 1)
		emit_context(rows, source, before_start, before_end)
		if before_end >= before_start then
			prev_emit = before_end
		end

		-- Removed lines show the source line number where they would
		-- sit (b_start for change/delete; clamped to 1 for topdelete).
		local removed = slice_text(removed_text, hunk.a_start, hunk.a_count)
		local removed_anchor = math.max(1, hunk.b_start)
		for j, l in ipairs(removed) do
			rows[#rows + 1] = {
				lnum = removed_anchor + j - 1,
				marker = "- ",
				text = l,
				hl = "BeastGitPreviewDelete",
			}
		end
		-- Added lines map to b_start .. b_start+b_count-1 in `source`.
		local added
		if hunk.b_count == 0 then
			added = {}
		elseif added_text then
			added = slice_text(added_text, hunk.b_start, hunk.b_count)
		else
			added = source.get_lines(hunk.b_start, hunk.b_start + hunk.b_count - 1)
		end
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
			emit_context(rows, source, after_start, after_end)
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
	api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	-- Stash the gutter table on the buffer so the window's statuscolumn can
	-- look up the synthetic line number + marker per row.
	vim.b[buf].beast_git_preview_gutter = gutters
	for i = 1, #body do
		if hls[i] then
			api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { line_hl_group = hls[i] })
		end
	end
end

--- Statuscolumn callback for preview floats. Reads the per-line gutter
--- record stashed by apply_decorations and returns a `%#hl#text` string.
---@return string
function M._statuscol()
	-- statuscolumn `%!` evaluates with the command-line window as current;
	-- resolve the *drawing* window via vim.g.statusline_winid so we read
	-- gutter data from the float's buffer, not whatever buffer is current.
	local winid = vim.g.statusline_winid or 0
	local buf = winid ~= 0 and vim.api.nvim_win_get_buf(winid) or vim.api.nvim_get_current_buf()
	local gutters = vim.b[buf].beast_git_preview_gutter
	if not gutters then
		return ""
	end
	local g = gutters[vim.v.lnum]
	if not g then
		return ""
	end
	return string.format("%%#%s#%s%%#%s#%s", g.lnum_hl, g.lnum_text, g.marker_hl, g.marker)
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
---@param gutter_w integer  display width of the per-row gutter
---@param source_ft string
---@param source_win integer
---@param anchor_lnum integer  1-indexed buffer line to anchor the float below
---@param title (string|table)?  optional title shown in the float border (string or chunks list)
---@return integer buf, integer win
local function open_float(body, hls, gutters, width, gutter_w, source_ft, source_win, anchor_lnum, title)
	local buf = View.buf.new("")
	api.nvim_buf_set_lines(buf, 0, -1, false, body)
	vim.bo[buf].modifiable = false
	vim.bo[buf].readonly = true

	maybe_start_treesitter(buf, source_ft)
	apply_decorations(buf, body, hls, gutters)

	local height = math.min(#body, math.max(1, resolve_max_height()))
	-- Offset left by the source window's gutter (statuscolumn/sign/number) so
	-- the float's left border sits at the window's true left edge instead of
	-- starting after the gutter.
	local textoff = (vim.fn.getwininfo(source_win)[1] or {}).textoff or 0
	local win_opts = {
		relative = "win",
		win = source_win,
		bufpos = { anchor_lnum - 1, 0 },
		row = 1,
		col = -textoff,
		width = width,
		height = height,
		border = "rounded",
		focusable = true,
		noautocmd = true,
	}
	if title and title ~= "" then
		win_opts.title = title
		win_opts.title_pos = "right"
	end
	local win = api.nvim_open_win(buf, false, win_opts)
	-- We skip `style = "minimal"` so we can keep `statuscolumn` writable
	-- (minimal blanks it). The options below replicate minimal's other
	-- effects so the float still looks chrome-free.
	vim.api.nvim_set_option_value("winhighlight", "Normal:BeastGitPreviewNormal,FloatBorder:BeastGitPreviewBorder", { win = win })
	vim.api.nvim_set_option_value("wrap", false, { win = win })
	-- 'statuscolumn' only allocates width when 'number'/'relativenumber' or
	-- 'signcolumn' is on; without one of those the callback runs but its
	-- output has nowhere to render. Turn 'number' on (statuscolumn overrides
	-- the actual number display) and explicitly size the column to match
	-- our gutter so the float doesn't flicker on focus changes.
	vim.api.nvim_set_option_value("number", true, { win = win })
	vim.api.nvim_set_option_value("relativenumber", false, { win = win })
	vim.api.nvim_set_option_value("numberwidth", math.max(1, gutter_w), { win = win })
	vim.api.nvim_set_option_value("cursorline", false, { win = win })
	vim.api.nvim_set_option_value("cursorcolumn", false, { win = win })
	vim.api.nvim_set_option_value("foldcolumn", "0", { win = win })
	vim.api.nvim_set_option_value("spell", false, { win = win })
	vim.api.nvim_set_option_value("list", false, { win = win })
	vim.api.nvim_set_option_value("signcolumn", "no", { win = win })
	vim.api.nvim_set_option_value("colorcolumn", "", { win = win })
	vim.api.nvim_set_option_value("statuscolumn", "%!v:lua.require'beast.libs.git.preview'._statuscol()", { win = win })
	return buf, win
end

---@param buf integer  preview buffer
---@param source_buf integer  buffer whose cursor opened the preview
---@param source_win integer
---@param hunk_lines table<integer, boolean>  set of buffer lines covered by matched hunks
---@param hunk_min integer  smallest line covered by matched hunks
---@param hunk_max integer  largest line covered by matched hunks
---@param recompute_width fun(): integer  re-derive float width from current source window
local function wire_close(buf, source_buf, source_win, hunk_lines, hunk_min, hunk_max, recompute_width)
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
			if not api.nvim_win_is_valid(source_win) then
				M.close()
				return
			end
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
			-- Recompute the source window's gutter width on every scroll: it
			-- changes as line numbers grow (e.g. 99 → 100) or as signs come
			-- and go, and the float must stay flush with the window edge.
			local textoff = (vim.fn.getwininfo(source_win)[1] or {}).textoff or 0
			pcall(api.nvim_win_set_config, current.win, {
				relative = "win",
				win = source_win,
				bufpos = { visible - 1, 0 },
				row = 1,
				col = -textoff,
			})
		end,
	})
	-- Recompute float width when the source window itself is resized
	-- (e.g. new split halves its width). WinScrolled doesn't fire on pure
	-- horizontal resizes, so width would otherwise stay stale.
	api.nvim_create_autocmd("WinResized", {
		group = group,
		callback = function()
			if not (current and current.win and api.nvim_win_is_valid(current.win)) then
				return
			end
			if not api.nvim_win_is_valid(source_win) then
				return
			end
			if not vim.tbl_contains(vim.v.event.windows or {}, source_win) then
				return
			end
			local textoff = (vim.fn.getwininfo(source_win)[1] or {}).textoff or 0
			pcall(api.nvim_win_set_config, current.win, {
				relative = "win",
				win = source_win,
				bufpos = { hunk_min - 1, 0 },
				row = 1,
				col = -textoff,
				width = recompute_width(),
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
---@param project? fun(b_start: integer): integer  index→buffer projection for staged hunks
---@return table<integer, boolean> hunk_lines, integer hunk_min, integer hunk_max
local function compute_hunk_extent(matched, project)
	local hunk_lines = {}
	local hunk_min, hunk_max = math.huge, -math.huge
	for _, h in ipairs(matched) do
		local s_raw = math.max(1, h.b_start or 1)
		local s = project and project(s_raw) or s_raw
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
---@param source_win integer  window the float will be anchored to
---@return integer
local function compute_width(mode, body, gutter_w, source_win)
	local win_w = api.nvim_win_get_width(source_win)
	if mode == "fit" then
		return math.min(max_width(body) + gutter_w + 2, math.floor(win_w * 0.8))
	end
	return math.max(1, win_w - 2)
end

---@class Beast.Git.PreviewOpts
---@field target? "unstaged" | "staged" | "auto"   default: "auto"

--- Translate the staged hunks (INDEX line space) into BUFFER lines and pick
--- those whose footprint overlaps `[s, e]`. Returns the matched hunks and
--- the projection function (used later to anchor the float).
---@param st Beast.Git.BufState
---@param s integer
---@param e integer
---@return Beast.Git.RawHunk[] matched, fun(b_start: integer): integer projection
local function staged_hunks_in_range(st, s, e)
	local hunks_mod = require("beast.libs.git.hunks")
	local project = function(b_start)
		return b_start + hunks_mod.index_to_buffer_delta(b_start == 0 and 1 or b_start, st.hunks)
	end
	local matched = {}
	for _, h in ipairs(st.staged_hunks) do
		local lo_idx = h.type == "delete" and (h.b_start == 0 and 1 or h.b_start) or h.b_start
		local hi_idx = h.type == "delete" and lo_idx or (h.b_start + h.b_count - 1)
		local lo_buf, hi_buf = project(lo_idx), project(hi_idx)
		if hi_buf >= s and lo_buf <= e then
			matched[#matched + 1] = h
		end
	end
	return matched, project
end

--- HEAD↔BUFFER diff — the union of staged + unstaged changes. Used when a
--- range spans both tiers so the user sees one continuous picture.
---@param st Beast.Git.BufState
---@param source_buf integer
---@return Beast.Git.RawHunk[]
local function compute_combined_hunks(st, source_buf)
	local current = table.concat(api.nvim_buf_get_lines(source_buf, 0, -1, false), "\n") .. "\n"
	return require("beast.libs.git.diff").compute_hunks(st.head, current)
end

---@class Beast.Git.PreviewPlan
---@field matched Beast.Git.RawHunk[]
---@field all_hunks Beast.Git.RawHunk[]    full hunk list for expand_adjacent context
---@field source Beast.Git.PreviewSource
---@field removed_text string
---@field added_text string?
---@field title (string|table)?
---@field project (fun(b_start: integer): integer)?

--- Decide which tier (or combination) to render, given an explicit target or
--- auto-detection from the range overlap. Returns nil when nothing applies
--- (in which case a notification has already been issued).
---@param opts Beast.Git.PreviewOpts?
---@param st Beast.Git.BufState
---@param source_buf integer
---@param s integer
---@param e integer
---@return Beast.Git.PreviewPlan?
local function plan_preview(opts, st, source_buf, s, e)
	local target = opts and opts.target or "auto"
	local matched_unstaged = hunks_in_range(st.hunks, s, e)
	local matched_staged, staged_project = staged_hunks_in_range(st, s, e)

	if target == "unstaged" then
		if #matched_unstaged == 0 then
			vim.notify("No unstaged hunk in selection", vim.log.levels.INFO, { title = "beast.git" })
			return nil
		end
		return {
			matched = matched_unstaged,
			all_hunks = st.hunks,
			source = buffer_source(source_buf),
			removed_text = st.base,
			added_text = nil,
			title = nil,
		}
	end

	if target == "staged" then
		if #matched_staged == 0 then
			vim.notify("No staged hunk in selection", vim.log.levels.INFO, { title = "beast.git" })
			return nil
		end
		return {
			matched = matched_staged,
			all_hunks = st.staged_hunks,
			source = string_source(st.base),
			removed_text = st.head,
			added_text = st.base,
			title = { { " Staged ", "BeastGitPreviewStagedTitle" } },
			project = staged_project,
		}
	end

	-- target == "auto": pick the tier(s) that intersect the range.
	if #matched_unstaged == 0 and #matched_staged == 0 then
		vim.notify("No hunk in selection", vim.log.levels.INFO, { title = "beast.git" })
		return nil
	end
	if #matched_unstaged > 0 and #matched_staged == 0 then
		return {
			matched = matched_unstaged,
			all_hunks = st.hunks,
			source = buffer_source(source_buf),
			removed_text = st.base,
			added_text = nil,
			title = nil,
		}
	end
	if #matched_staged > 0 and #matched_unstaged == 0 then
		return {
			matched = matched_staged,
			all_hunks = st.staged_hunks,
			source = string_source(st.base),
			removed_text = st.head,
			added_text = st.base,
			title = { { " Staged ", "BeastGitPreviewStagedTitle" } },
			project = staged_project,
		}
	end

	-- Mixed: compute the union HEAD↔BUFFER diff and filter to the range.
	-- This naturally handles overlapping/abutting staged + unstaged hunks
	-- (matches `git diff HEAD -- <file>`).
	local combined = compute_combined_hunks(st, source_buf)
	local matched_combined = hunks_in_range(combined, s, e)
	if #matched_combined == 0 then
		-- Should not happen given the per-tier matches, but bail safely.
		vim.notify("No hunk in selection", vim.log.levels.INFO, { title = "beast.git" })
		return nil
	end
	return {
		matched = matched_combined,
		all_hunks = combined,
		source = buffer_source(source_buf),
		removed_text = st.head,
		added_text = nil,
		title = { { " HEAD↔buffer ", "BeastGitPreviewStagedTitle" } },
	}
end

---@param opts Beast.Git.PreviewOpts?
function M.open_for_current_line(opts)
	if focus_if_open() then
		return
	end
	local cursor = api.nvim_win_get_cursor(0)[1]
	M.open_for_range(cursor, cursor, opts)
end

---@param range_start integer
---@param range_end integer
---@param opts Beast.Git.PreviewOpts?
function M.open_for_range(range_start, range_end, opts)
	if focus_if_open() then
		return
	end
	if range_start > range_end then
		range_start, range_end = range_end, range_start
	end

	local git = require("beast.libs.git")
	local st = git._get_state()
	if not st then
		return
	end

	local source_buf = api.nvim_get_current_buf()
	local plan = plan_preview(opts, st, source_buf, range_start, range_end)
	if not plan then
		return
	end

	local config = require("beast.libs.git.config")
	local preview_cfg = config.preview or {}
	local ctx_n = preview_cfg.context_size or 0
	-- Auto-cluster adjacent hunks so back-to-back changes preview together.
	local matched = expand_adjacent(plan.all_hunks, plan.matched, preview_cfg.adjacent_gap or 0)

	local rows = build_rows(plan.source, plan.removed_text, plan.added_text, matched, ctx_n)
	if #rows == 0 then
		return
	end
	local body, hls, gutters, gutter_w = render_rows(rows)

	local source_ft = vim.bo[source_buf].filetype
	local source_win = api.nvim_get_current_win()
	local hunk_lines, hunk_min, hunk_max = compute_hunk_extent(matched, plan.project)
	local width_mode = preview_cfg.width
	local recompute_width = function()
		return compute_width(width_mode, body, gutter_w, source_win)
	end
	local width = recompute_width()

	M.close()
	local buf, win = open_float(body, hls, gutters, width, gutter_w, source_ft, source_win, hunk_min, plan.title)
	current = PreviewView(buf, win)
	wire_close(buf, source_buf, source_win, hunk_lines, hunk_min, hunk_max, recompute_width)
end

-- Test-only seam — exposes pure helpers for unit tests.
M._test = { build_rows = build_rows, render_rows = render_rows, expand_adjacent = expand_adjacent }

return M
