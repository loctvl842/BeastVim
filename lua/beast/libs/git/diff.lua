-- Diff wrapper around Neovim's built-in vim.text.diff / vim.diff.
--
-- compute_hunks(base, current) → list of hunks:
--   { a_start, a_count, b_start, b_count, type }
-- where `type` ∈ "add" | "change" | "delete".
-- Higher-level expansion to per-line markers (topdelete / changedelete) lives
-- in hunks.lua.

local M = {}

---@class Beast.Git.RawHunk
---@field a_start integer 1-based start line in base (0 when a_count == 0)
---@field a_count integer
---@field b_start integer 1-based start line in current (0 when b_count == 0)
---@field b_count integer
---@field type "add" | "change" | "delete"

--- Backend: prefer vim.text.diff (≥ 0.11) over vim.diff (≥ 0.10).
---@diagnostic disable-next-line: deprecated
local diff_fn = (vim.text and vim.text.diff) or vim.diff

M.backend = (vim.text and vim.text.diff) and "vim.text.diff" or "vim.diff"

local DIFF_OPTS = {
	result_type = "indices",
	algorithm = "histogram",
	linematch = 60,
	ignore_blank_lines = false,
}

---@param base string
---@param current string
---@return Beast.Git.RawHunk[]
function M.compute_hunks(base, current)
	if not diff_fn then
		return {}
	end
	local ok, raw = pcall(diff_fn, base, current, DIFF_OPTS)
	if not ok or type(raw) ~= "table" then
		return {}
	end
	local hunks = {}
	for i = 1, #raw do
		local r = raw[i]
		local a_start, a_count, b_start, b_count = r[1], r[2], r[3], r[4]
		local kind
		if a_count == 0 then
			kind = "add"
		elseif b_count == 0 then
			kind = "delete"
		else
			kind = "change"
		end
		hunks[i] = {
			a_start = a_start,
			a_count = a_count,
			b_start = b_start,
			b_count = b_count,
			type = kind,
		}
	end
	return hunks
end

-- ---------------------------------------------------------------------------
-- Word-level spans
-- ---------------------------------------------------------------------------

local WORD_MAX_BYTES = 1000 -- longer lines skip emphasis (keeps big hunks instant)
local WORD_MIN_SHARED = 0.4 -- min shared non-whitespace ratio (vs the shorter line), else lines are "too different"

---@class Beast.Git.Token
---@field text string
---@field s integer 0-based start byte
---@field e integer exclusive end byte
---@field space boolean

--- Split a line into word runs, whitespace runs and single other characters
--- (a whole UTF-8 sequence counts as one character).
---@param line string
---@return Beast.Git.Token[]
local function tokenize(line)
	local tokens, i, n = {}, 1, #line
	while i <= n do
		local text = line:match("^[%w_]+", i) or line:match("^%s+", i) or line:match("^[%z\1-\127\194-\244][\128-\191]*", i)
		tokens[#tokens + 1] = { text = text, s = i - 1, e = i - 1 + #text, space = text:find("^%s") ~= nil }
		i = i + #text
	end
	return tokens
end

---@param tokens Beast.Git.Token[]
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
---@param tokens Beast.Git.Token[]
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

---@param tokens Beast.Git.Token[]
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

return M
