-- Shared diff renderer: rows of code (with their line numbers and a -/+ mark) become buffer text, row
-- tints, changed-word marks and a number gutter drawn by the window's 'statuscolumn'. The git hunk float
-- and the finder preview both draw with it.
--
-- A row is { text, sign = "-" | "+" | " ", old?, new?, spans? }: `text` is the code only (no mark), `old`
-- and `new` the line numbers on each side, `spans` the byte ranges of the words that changed.
--
-- render(rows, { columns }) -> Rendered   pure; columns = 1 shows `new` only, 2 shows `old` and `new`
-- paint(buf, rendered) / clear(buf)       extmarks + the gutter the statuscolumn reads
-- attach(win, width) / detach(win)        the window options the gutter needs

local api = vim.api

local M = {}

--- Backend: prefer vim.text.diff (≥ 0.11) over vim.diff (≥ 0.10).
---@diagnostic disable-next-line: deprecated
local diff_fn = (vim.text and vim.text.diff) or vim.diff

-- ---------------------------------------------------------------------------
-- Word-level spans
-- ---------------------------------------------------------------------------

local WORD_MAX_BYTES = 1000 -- longer lines skip emphasis (keeps big hunks instant)
local WORD_MIN_SHARED = 0.4 -- min shared non-whitespace ratio (vs the shorter line), else lines are "too different"

---@class Beast.View.DiffToken
---@field text string
---@field s integer 0-based start byte
---@field e integer exclusive end byte
---@field space boolean

--- Split a line into word runs, whitespace runs and single other characters
--- (a whole UTF-8 sequence counts as one character; a stray invalid byte is
--- its own token).
---@param line string
---@return Beast.View.DiffToken[]
local function tokenize(line)
	local tokens, i, n = {}, 1, #line
	while i <= n do
		local text = line:match("^[%w_]+", i) or line:match("^%s+", i) or line:match("^[%z\1-\127\194-\244][\128-\191]*", i) or line:sub(i, i)
		tokens[#tokens + 1] = { text = text, s = i - 1, e = i - 1 + #text, space = text:find("^%s") ~= nil }
		i = i + #text
	end
	return tokens
end

---@param tokens Beast.View.DiffToken[]
---@return string
local function token_lines(tokens)
	local texts = {}
	for i, t in ipairs(tokens) do
		texts[i] = t.text
	end
	return table.concat(texts, "\n") .. "\n"
end

--- Merge runs of changed tokens into byte spans, bridging a lone unchanged
--- whitespace token between two changed ones.
---@param tokens Beast.View.DiffToken[]
---@param changed table<integer, boolean>
---@return integer[][] spans { {s, e}, ... } 0-based, end exclusive
local function merge_spans(tokens, changed)
	local spans, i = {}, 1
	while i <= #tokens do
		if changed[i] then
			local first, last = i, i
			while true do
				if changed[last + 1] then
					last = last + 1
				elseif tokens[last + 1] and tokens[last + 1].space and changed[last + 2] then
					last = last + 2
				else
					break
				end
			end
			spans[#spans + 1] = { tokens[first].s, tokens[last].e }
			i = last + 1
		else
			i = i + 1
		end
	end
	return spans
end

---@param tokens Beast.View.DiffToken[]
---@param changed table<integer, boolean>
---@return integer total, integer kept non-whitespace byte counts
local function nonspace_bytes(tokens, changed)
	local total, kept = 0, 0
	for i, t in ipairs(tokens) do
		if not t.space then
			total = total + #t.text
			if not changed[i] then
				kept = kept + #t.text
			end
		end
	end
	return total, kept
end

--- Which tokens on each side fall in a diff hunk.
---@param raw integer[][]
---@return table<integer, boolean> old_changed, table<integer, boolean> new_changed
local function changed_tokens(raw)
	local old_changed, new_changed = {}, {}
	for _, r in ipairs(raw) do
		for i = r[1], r[1] + r[2] - 1 do
			old_changed[i] = true
		end
		for i = r[3], r[3] + r[4] - 1 do
			new_changed[i] = true
		end
	end
	return old_changed, new_changed
end

--- Byte spans of the words that differ between two versions of a line.
--- Returns nil when emphasis would only add noise: lines too long, or
--- sharing too little text to read as an edit of one another.
---@param old string
---@param new string
---@return integer[][]? old_spans, integer[][]? new_spans  { {s, e}, ... } 0-based, end exclusive
function M.word_spans(old, new)
	if not diff_fn or #old > WORD_MAX_BYTES or #new > WORD_MAX_BYTES then
		return nil, nil
	end
	local old_tokens, new_tokens = tokenize(old), tokenize(new)
	local ok, raw = pcall(diff_fn, token_lines(old_tokens), token_lines(new_tokens), {
		result_type = "indices",
		algorithm = "histogram",
	})
	if not ok or type(raw) ~= "table" then
		return nil, nil
	end
	local old_changed, new_changed = changed_tokens(raw)
	local old_total, old_kept = nonspace_bytes(old_tokens, old_changed)
	local new_total = nonspace_bytes(new_tokens, new_changed)
	if old_kept < WORD_MIN_SHARED * math.min(old_total, new_total) then
		return nil, nil
	end
	return merge_spans(old_tokens, old_changed), merge_spans(new_tokens, new_changed)
end

-- ---------------------------------------------------------------------------
-- Pairing
-- ---------------------------------------------------------------------------

--- Fill `spans` on the rows of a change block: the j-th removed row is compared with the j-th added row
--- (surplus rows stay without emphasis).
---@param removed Beast.View.DiffRow[]
---@param added Beast.View.DiffRow[]
function M.pair(removed, added)
	for j, row in ipairs(added) do
		if removed[j] then
			removed[j].spans, row.spans = M.word_spans(removed[j].text, row.text)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

---@class Beast.View.DiffRow
---@field text string code of the row, without the -/+ mark
---@field sign "-" | "+" | " "
---@field old? integer line number on the old side
---@field new? integer line number on the new side
---@field spans? integer[][] byte ranges {s, e} (0-based, end exclusive) of the words that changed
---@field plain? boolean not code (a header, a band, a note): blank gutter, tinted by `hl` instead of `sign`
---@field hl? string background group of a plain row
---@field marks? { [1]: integer, [2]: integer, [3]: string }[] extra highlights {s, e, group} inside the line

---@class Beast.View.DiffChunk
---@field text string
---@field hl string

---@class Beast.View.DiffRendered
---@field body string[] one buffer line per row
---@field hls table<integer, string> row → background group of its whole line
---@field spans table<integer, { hl: string, ranges: integer[][] }> row → changed-word ranges
---@field marks table<integer, { [1]: integer, [2]: integer, [3]: string }[]> row → extra highlights
---@field gutters Beast.View.DiffChunk[][] row → the chunks the statuscolumn draws
---@field width integer display width of the gutter

local LINE_HL = { ["-"] = "BeastViewDiffDelete", ["+"] = "BeastViewDiffAdd" }
local SIGN_HL = { ["-"] = "BeastViewDiffDeleteSign", ["+"] = "BeastViewDiffAddSign" }

---@param rows Beast.View.DiffRow[]
---@param opts { columns: 1 | 2 }
---@return Beast.View.DiffRendered
function M.render(rows, opts)
	local widest = 0
	for _, r in ipairs(rows) do
		widest = math.max(widest, r.old or 0, r.new or 0)
	end
	local w = math.max(2, #tostring(widest))
	local two = opts.columns == 2
	local width = (two and 2 * w + 2 or w + 1) + 2

	---@param n integer?
	local function num(n)
		local s = n and tostring(n) or ""
		return string.rep(" ", w - #s) .. s
	end

	local body, hls, spans, marks, gutters = {}, {}, {}, {}, {}
	for i, r in ipairs(rows) do
		body[i] = r.text
		marks[i] = r.marks
		if r.plain then
			gutters[i] = { { text = string.rep(" ", width), hl = r.hl or "Normal" } }
			hls[i] = r.hl
		else
			local sign_hl = SIGN_HL[r.sign] or "LineNr"
			local numbers = two and (num(r.old) .. " " .. num(r.new) .. " ") or (num(r.new) .. " ")
			gutters[i] = { { text = numbers, hl = sign_hl }, { text = r.sign .. " ", hl = sign_hl } }
			hls[i] = LINE_HL[r.sign]
			if r.spans and #r.spans > 0 then
				spans[i] = { hl = LINE_HL[r.sign] .. "Word", ranges = r.spans }
			end
		end
	end
	return { body = body, hls = hls, spans = spans, marks = marks, gutters = gutters, width = width }
end

-- ---------------------------------------------------------------------------
-- Painting
-- ---------------------------------------------------------------------------

local ns = api.nvim_create_namespace("beast_view_diff")

--- Gutter of each painted buffer. A Lua table, not a buffer variable: the statuscolumn reads it once per
--- screen row, and a buffer variable would be copied to a Vimscript dict on every read.
---@type table<integer, Beast.View.DiffChunk[][]>
local gutters = {}

---@param buf integer
---@param rendered Beast.View.DiffRendered
function M.paint(buf, rendered)
	api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	if not gutters[buf] then
		api.nvim_create_autocmd("BufWipeout", {
			buffer = buf,
			once = true,
			callback = function()
				gutters[buf] = nil
			end,
		})
	end
	gutters[buf] = rendered.gutters
	for i = 1, #rendered.body do
		if rendered.hls[i] then
			-- A range highlight (not line_hl_group, which always paints over ranges)
			-- so the changed-word backgrounds below can layer on top of it.
			api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { end_row = i, end_col = 0, hl_group = rendered.hls[i], hl_eol = true, priority = 100 })
		end
		local span = rendered.spans[i]
		for _, range in ipairs(span and span.ranges or {}) do
			api.nvim_buf_set_extmark(buf, ns, i - 1, range[1], { end_col = range[2], hl_group = span.hl, priority = 200 })
		end
		for _, m in ipairs(rendered.marks[i] or {}) do
			api.nvim_buf_set_extmark(buf, ns, i - 1, m[1], { end_col = m[2], hl_group = m[3], priority = 150 })
		end
	end
end

---@param buf integer
function M.clear(buf)
	api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	gutters[buf] = nil
end

--- The text the statuscolumn shows for one screen row. The rows a long line wraps onto (`virtnum` > 0) show
--- no numbers, only the same width in the color of the row's mark, so its tint carries on.
---@param chunks Beast.View.DiffChunk[]?
---@param virtnum? integer
---@return string
function M.gutter_text(chunks, virtnum)
	if not chunks then
		return ""
	end
	if virtnum and virtnum ~= 0 then
		local width = 0
		for _, c in ipairs(chunks) do
			width = width + #c.text
		end
		return ("%%#%s#%s"):format(chunks[#chunks].hl, string.rep(" ", width))
	end
	local out = {}
	for _, c in ipairs(chunks) do
		out[#out + 1] = ("%%#%s#%s"):format(c.hl, c.text)
	end
	return table.concat(out)
end

--- Statuscolumn callback of the windows `attach` was called for.
---@return string
function M.statuscol()
	-- statuscolumn `%!` evaluates with the command-line window as current;
	-- resolve the *drawing* window via vim.g.statusline_winid so we read
	-- gutter data from the window's buffer, not whatever buffer is current.
	local winid = vim.g.statusline_winid or 0
	local buf = winid ~= 0 and api.nvim_win_get_buf(winid) or api.nvim_get_current_buf()
	return M.gutter_text(gutters[buf] and gutters[buf][vim.v.lnum], vim.v.virtnum)
end

local OPTIONS = {
	number = true,
	relativenumber = false,
	cursorline = false,
	cursorcolumn = false,
	foldcolumn = "0",
	spell = false,
	list = false,
	signcolumn = "no",
	colorcolumn = "",
	statuscolumn = "%!v:lua.require'beast.libs.view.diff'.statuscol()",
}

--- What each attached window had before, for `detach`.
---@type table<integer, table<string, any>>
local before = {}

--- Give `win` the options its gutter needs. 'statuscolumn' only allocates width when 'number' (or a sign
--- column) is on, so 'number' is turned on (the statuscolumn replaces the real number display) and its
--- width is set to the gutter's, so the window does not shift when focus changes.
---@param win integer
---@param width integer gutter width, from `render`
function M.attach(win, width)
	local saved = before[win]
	if not saved then
		saved = {}
		for name in pairs(OPTIONS) do
			saved[name] = api.nvim_get_option_value(name, { win = win })
		end
		saved.numberwidth = api.nvim_get_option_value("numberwidth", { win = win })
		before[win] = saved
		api.nvim_create_autocmd("WinClosed", {
			pattern = tostring(win),
			once = true,
			callback = function()
				before[win] = nil
			end,
		})
	end
	for name, value in pairs(OPTIONS) do
		api.nvim_set_option_value(name, value, { win = win })
	end
	api.nvim_set_option_value("numberwidth", math.max(1, width), { win = win })
end

--- Give `win` back the options it had before `attach`.
---@param win integer
function M.detach(win)
	local saved = before[win]
	if not saved then
		return
	end
	before[win] = nil
	if not api.nvim_win_is_valid(win) then
		return
	end
	for name, value in pairs(saved) do
		api.nvim_set_option_value(name, value, { win = win })
	end
end

return M
