local TopK = require("beast.libs.finder.topk")
local async = require("beast.libs.async")

local M = {}

-- Scoring constants (fzf-compatible)
local SCORE_MATCH = 16
local SCORE_GAP_START = -3
local SCORE_GAP_EXTENSION = -1
local BONUS_FIRST_CHAR = 16 -- applied when match starts at index 1
local BONUS_BOUNDARY = 8
local BONUS_CONSECUTIVE = 4
local BONUS_CAMEL = 7

-- Characters that mark a word boundary predecessor
local BOUNDARY_CHARS = {
	[string.byte("/")] = true,
	[string.byte("\\")] = true,
	[string.byte("_")] = true,
	[string.byte("-")] = true,
	[string.byte(".")] = true,
	[string.byte(" ")] = true,
}

-- ---------------------------------------------------------------------------
-- Pattern parsing
-- ---------------------------------------------------------------------------
---@class Beast.Finder.Term
---@field text string
---@field inverse boolean
---@field exact boolean
---@field prefix boolean
---@field suffix boolean
---@field ignorecase boolean

---@param raw string
---@param ignorecase boolean
---@param smartcase boolean
---@return Beast.Finder.Term[][]  AND-groups of OR-terms
local function parse_pattern(raw, ignorecase, smartcase)
	local and_groups = {} ---@type Beast.Finder.Term[][]
	for _, and_part in ipairs(vim.split(raw, "%s+", { trimempty = true })) do
		local or_terms = {} ---@type Beast.Finder.Term[]
		for _, or_part in ipairs(vim.split(and_part, "|", { plain = true, trimempty = true })) do
			local text = or_part
			local inverse, exact, prefix, suffix = false, false, false, false
			if text:sub(1, 1) == "!" then
				inverse = true
				text = text:sub(2)
			end
			if text:sub(1, 1) == "^" then
				prefix = true
				text = text:sub(2)
			elseif text:sub(1, 1) == "'" then
				exact = true
				text = text:sub(2)
			end
			if text:sub(-1) == "$" then
				suffix = true
				text = text:sub(1, -2)
			end
			if text ~= "" then
				local ic = ignorecase
				if smartcase and text:match("%u") then
					ic = false
				end
				if ic then
					text = text:lower()
				end
				or_terms[#or_terms + 1] = { text = text, inverse = inverse, exact = exact, prefix = prefix, suffix = suffix, ignorecase = ic }
			end
		end
		if #or_terms > 0 then
			and_groups[#and_groups + 1] = or_terms
		end
	end
	return and_groups
end

-- ---------------------------------------------------------------------------
-- Scoring
-- ---------------------------------------------------------------------------

---Scores how well a search term (`needle`) matches inside a candidate string (`hay`).
---
---This is a lightweight fuzzy matcher inspired by fzf-style scoring.
---
---Supports:
---  • exact match        : `'abc`
---  • prefix match       : `^abc`
---  • suffix match       : `abc$`
---  • fuzzy match        : `abc`
---
---Fuzzy matching rules:
---  • characters must appear in-order
---  • consecutive matches score higher
---  • word-boundary matches score higher
---  • camelCase matches score higher
---  • shorter/tighter match windows score higher
---  • large gaps reduce score
---
---Examples:
---
---```text
---needle: "bf"
---hay   : "beast_finder.lua"
---
---b east_ f inder.lua
---^       ^
---
---=> valid fuzzy match
---```
---
---```text
---needle: "^src"
---hay   : "src/finder.lua"
---
---=> valid prefix match
---```
---
---```text
---needle: "lua$"
---hay   : "finder.lua"
---
---=> valid suffix match
---```
---
---```text
---needle: "'finder"
---hay   : "beast finder plugin"
---
---=> exact substring match
---```
---
---@param hay string
---Candidate text to search inside (haystack).
---
---If ignorecase is enabled, this string should already be lowercased.
---
---@param needle string
---Search pattern text (needle).
---
---If ignorecase is enabled, this string should already be lowercased.
---
---@param prefix boolean
---Require match to begin at index 1.
---
---Example:
---  "^src" matches:
---    "src/main.lua"
---
---  but not:
---    "my/src/main.lua"
---
---@param suffix boolean
---Require match to end at final character.
---
---Example:
---  "lua$" matches:
---    "finder.lua"
---
---  but not:
---    "lua/config"
---
---@param exact boolean
---Disable fuzzy matching and require plain substring match.
---
---Example:
---  "'finder" matches:
---    "beast finder plugin"
---
---  but not fuzzy-separated chars like:
---    "f_x_i_x_n_x_d_x_e_x_r"
---
---@return number score
---Match score.
---
---Higher score = better match.
---
---0 means no valid match.
---
---@return integer[]? positions
---1-based byte positions of matched characters inside `hay`.
---
---Used for highlight rendering.
---
---Example:
---
---```text
---hay      = "beastfinder"
---needle   = "bf"
---positions = {1, 6}
---
---b e a s t f i n d e r
---^         ^
---```
local function score_term(hay, needle, prefix, suffix, exact)
	local hlen = #hay
	local nlen = #needle

	-- Reject impossible matches early.
	if nlen == 0 or nlen > hlen then
		return 0, nil
	end

	-- ---------------------------------------------------------------------
	-- Exact / prefix / suffix matching
	-- ---------------------------------------------------------------------
	--
	-- These modes bypass fuzzy scoring entirely and use plain substring
	-- matching instead.
	--
	-- Examples:
	--
	--   exact:
	--     "'finder"
	--
	--   prefix:
	--     "^src"
	--
	--   suffix:
	--     "lua$"
	--
	if exact or prefix or suffix then
		local idx = hay:find(needle, 1, true)

		if not idx then
			return 0, nil
		end

		-- Prefix mode requires match at first character.
		if prefix and idx ~= 1 then
			return 0, nil
		end

		-- Suffix mode requires match at end of string.
		if suffix and idx + nlen - 1 ~= hlen then
			return 0, nil
		end

		local base = SCORE_MATCH * nlen

		-- Reward matches beginning at first character.
		if idx == 1 then
			base = base + BONUS_FIRST_CHAR
		end

		-- Collect highlight positions.
		local pos = {}

		for i = idx, idx + nlen - 1 do
			pos[#pos + 1] = i
		end

		return base, pos
	end

	-- ---------------------------------------------------------------------
	-- Fuzzy matching
	-- ---------------------------------------------------------------------
	--
	-- Convert strings into byte arrays for faster comparisons.
	--
	-- Example:
	--
	--   "abc"
	--
	-- becomes:
	--
	--   {97, 98, 99}
	--
	local hbytes = hay
	local nbytes = needle
	local byte = string.byte

	-- ---------------------------------------------------------------------
	-- Forward scan
	-- ---------------------------------------------------------------------
	--
	-- Find whether all needle characters exist in-order inside haystack.
	--
	local first_match = -1
	local ni = 1

	for hi = 1, hlen do
		if byte(hbytes, hi) == byte(nbytes, ni) then
			if ni == 1 then
				first_match = hi
			end

			ni = ni + 1

			-- Entire needle matched.
			if ni > nlen then
				break
			end
		end
	end

	-- Not all characters matched.
	if ni <= nlen then
		return 0, nil
	end

	-- ---------------------------------------------------------------------
	-- Backward scan
	-- ---------------------------------------------------------------------
	--
	-- Tighten the fuzzy match window.
	--
	-- Forward scan proves:
	--   "the match exists"
	--
	-- Backward scan finds:
	--   "the smallest useful matching window"
	--
	-- Example:
	--
	--   hay    = "b____f____i"
	--   needle = "bfi"
	--
	-- Produces a tighter score region.
	--
	local last_match = 0

	do
		local nj = nlen

		for hi = hlen, first_match, -1 do
			if byte(hbytes, hi) == byte(nbytes, nj) then
				-- First backward match = end of window.
				if nj == nlen then
					last_match = hi
				end

				nj = nj - 1

				-- Entire needle reconstructed backward.
				if nj == 0 then
					first_match = hi
					break
				end
			end
		end
	end

	-- ---------------------------------------------------------------------
	-- Score the final match window
	-- ---------------------------------------------------------------------
	--
	-- Rewards:
	--   • consecutive matches
	--   • boundary matches
	--   • camelCase matches
	--   • first-character matches
	--
	-- Penalizes:
	--   • gaps
	--
	local score = 0
	local positions = {}

	local in_gap = false
	ni = 1

	for hi = first_match, last_match do
		local hb = byte(hbytes, hi)

		-- -----------------------------------------------------------------
		-- Matched next needle character
		-- -----------------------------------------------------------------
		if hb == byte(nbytes, ni) then
			score = score + SCORE_MATCH

			positions[#positions + 1] = hi

			-- Match starts at first character.
			if hi == 1 then
				score = score + BONUS_FIRST_CHAR

			-- Match after separators
			elseif BOUNDARY_CHARS[byte(hbytes, hi - 1)] then
				score = score + BONUS_BOUNDARY

			-- camelCase boundary
			elseif hb >= 65 and hb <= 90 and byte(hbytes, hi - 1) >= 97 and byte(hbytes, hi - 1) <= 122 then
				score = score + BONUS_CAMEL

			-- Consecutive match bonus
			elseif ni > 1 then
				score = score + BONUS_CONSECUTIVE
			end

			in_gap = false

			ni = ni + 1

			if ni > nlen then
				break
			end

		-- -----------------------------------------------------------------
		-- Gap penalty
		-- -----------------------------------------------------------------
		--
		-- Compact matches are better than sparse matches.
		--
		-- Example:
		--
		--   good:
		--     "finder"
		--      ^^^
		--
		--   worse:
		--     "f___i___n"
		--
		else
			if in_gap then
				score = score + SCORE_GAP_EXTENSION
			else
				score = score + SCORE_GAP_START
				in_gap = true
			end
		end
	end

	return math.max(0, score), positions
end
---@param item Beast.Finder.Item
---@param and_groups Beast.Finder.Term[][]
---@return number score 0 = excluded
---@return integer[]? positions 1-based byte indices into item.text
local function score_item(item, and_groups)
	if #and_groups == 0 then
		return 1, nil
	end
	local hay_orig = item.text or ""
	-- Cache lowered text to avoid re-allocation on subsequent match cycles
	local hay_lower = item._lower
	if not hay_lower then
		hay_lower = hay_orig:lower()
		item._lower = hay_lower
	end
	local total = 0
	local all_positions = {}
	for _, or_terms in ipairs(and_groups) do
		local best = 0
		local best_pos = nil
		local any_match = false
		for _, term in ipairs(or_terms) do
			local hay = term.ignorecase and hay_lower or hay_orig
			local s, pos = score_term(hay, term.text, term.prefix, term.suffix, term.exact)
			if term.inverse then
				if s == 0 then
					best = math.max(best, 1)
					any_match = true
				end
			else
				if s > 0 then
					if s > best then
						best = s
						best_pos = pos
					end
					any_match = true
				end
			end
		end
		if not any_match then
			return 0, nil
		end
		if best_pos then
			for _, p in ipairs(best_pos) do
				all_positions[#all_positions + 1] = p
			end
		end
		total = total + best
	end
	return total, all_positions
end

-- ---------------------------------------------------------------------------
-- Subset detection
-- ---------------------------------------------------------------------------

--- Returns true when `new_pattern` is a strict superset of `old_pattern`
--- (user only appended characters — no deletions, insertions, or edits).
---@param old_pattern string
---@param new_pattern string
---@return boolean
local function is_superset(old_pattern, new_pattern)
	-- stylua: ignore
	if old_pattern == "" or new_pattern == "" then return false end
	-- stylua: ignore
	if #new_pattern <= #old_pattern then return false end
	return new_pattern:sub(1, #old_pattern) == old_pattern
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

---@class Beast.Finder.MatcherOpts
---@field smartcase boolean
---@field ignorecase boolean

---@class Beast.Finder.MatchState
---@field pattern string the pattern used in the last run
---@field scores table<integer, number> map of item.idx → score from last run

---@param items Beast.Finder.Item[]
---@param filter Beast.Finder.Filter
---@param cfg Beast.Finder.MatcherOpts
---@param on_done fun(matched: Beast.Finder.Item[], state: Beast.Finder.MatchState)
---@param prev_state? Beast.Finder.MatchState
---@param topk_capacity? integer defaults to 1000
function M.run(items, filter, cfg, on_done, prev_state, topk_capacity)
	async.spawn(function()
		local pattern = filter.pattern
		local scores = {} ---@type table<integer, number>

		-- Empty pattern fast-path: all items match with score=1, insertion order
		if pattern == "" then
			local capacity = topk_capacity or 1000
			local count = math.min(#items, capacity)
			local result = {}
			for i = 1, #items do
				items[i].score = 1
				items[i].positions = nil
				scores[items[i].idx] = 1
				if i <= count then
					result[i] = items[i]
				end
			end
			vim.schedule(function()
				on_done(result, { pattern = pattern, scores = scores })
			end)
			return
		end

		local groups = parse_pattern(pattern, cfg.ignorecase, cfg.smartcase)
		local capacity = topk_capacity or 1000
		local topk = TopK(capacity)
		local yield = async.yielder(1)

		-- Determine if we can use subset elimination
		local use_subset = prev_state and is_superset(prev_state.pattern, pattern)
		local prev_scores = use_subset and prev_state.scores or nil

		for i = 1, #items do
			local item = items[i]

			-- Subset elimination: skip items that failed the previous (shorter) query
			if prev_scores and prev_scores[item.idx] == 0 then
				item.score = 0
				item.positions = nil
				scores[item.idx] = 0
			else
				local s, pos = score_item(item, groups)
				item.score = s
				item.positions = pos
				scores[item.idx] = s
				if s > 0 then
					topk:push(item)
				end
			end
			yield()
		end

		local matched = topk:sorted()
		vim.schedule(function()
			on_done(matched, { pattern = pattern, scores = scores })
		end)
	end)
end

return M
