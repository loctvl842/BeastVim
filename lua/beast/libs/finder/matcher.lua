local async = require("beast.libs.finder.async")

-- Scoring constants (fzf-compatible)
local SCORE_MATCH = 16
local SCORE_GAP_START = -3
local SCORE_GAP_EXTENSION = -1
local BONUS_BOUNDARY = 8
local BONUS_CAMEL = 7
local BONUS_CONSECUTIVE = 4
local BONUS_FIRST_CHAR = 16 -- applied when match starts at index 1

-- Characters that mark a word boundary predecessor
local BOUNDARY_CHARS = {
	[string.byte("/")] = true,
	[string.byte("\\")] = true,
	[string.byte("_")] = true,
	[string.byte("-")] = true,
	[string.byte(".")] = true,
	[string.byte(" ")] = true,
}

local M = {}

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
	if raw == "" then
		return {}
	end
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

---@param hay string subject to search (already case-folded if ignorecase)
---@param needle string pattern term text (already case-folded)
---@param prefix boolean must match at start
---@param suffix boolean must match at end
---@param exact boolean substring match, no gap penalty
---@return number score (0 = no match)
local function score_term(hay, needle, prefix, suffix, exact)
	local hlen = #hay
	local nlen = #needle
	if nlen == 0 or nlen > hlen then
		return 0
	end

	-- Exact / prefix / suffix shortcuts
	if exact or prefix or suffix then
		local idx = hay:find(needle, 1, true)
		if not idx then
			return 0
		end
		if prefix and idx ~= 1 then
			return 0
		end
		if suffix and idx + nlen - 1 ~= hlen then
			return 0
		end
		local base = SCORE_MATCH * nlen
		if idx == 1 then
			base = base + BONUS_FIRST_CHAR
		end
		return base
	end

	-- Fuzzy: forward scan to find first match
	local hbytes = { hay:byte(1, hlen) }
	local nbytes = { needle:byte(1, nlen) }

	local first_match = -1
	local ni = 1
	for hi = 1, hlen do
		if hbytes[hi] == nbytes[ni] then
			if ni == 1 then
				first_match = hi
			end
			ni = ni + 1
			if ni > nlen then
				break
			end
		end
	end
	if ni <= nlen then
		return 0
	end

	-- Backward scan from first_match to find tightest window
	-- Walk backwards through needle from the last matched position
	local last_hi = hlen
	for hi = hlen, first_match, -1 do
		if hbytes[hi] == nbytes[nlen] then
			last_hi = hi
			break
		end
	end

	-- Score the window [first_match .. last_hi]
	local score = 0
	local in_gap = false
	ni = 1
	for hi = first_match, last_hi do
		local hb = hbytes[hi]
		if hb == nbytes[ni] then
			score = score + SCORE_MATCH
			-- Boundary bonus
			if hi == 1 then
				score = score + BONUS_FIRST_CHAR
			elseif BOUNDARY_CHARS[hbytes[hi - 1]] then
				score = score + BONUS_BOUNDARY
			elseif hb >= 65 and hb <= 90 and hbytes[hi - 1] >= 97 and hbytes[hi - 1] <= 122 then
				-- camelCase: uppercase after lowercase
				score = score + BONUS_CAMEL
			elseif ni > 1 then
				score = score + BONUS_CONSECUTIVE
			end
			in_gap = false
			ni = ni + 1
			if ni > nlen then
				break
			end
		else
			if in_gap then
				score = score + SCORE_GAP_EXTENSION
			else
				score = score + SCORE_GAP_START
				in_gap = true
			end
		end
	end

	return math.max(0, score)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

---@param item Beast.Finder.Item
---@param and_groups Beast.Finder.Term[][]
---@return number score 0 = excluded
local function score_item(item, and_groups)
	if #and_groups == 0 then
		return 1
	end
	local hay_orig = item.text or ""
	local hay_lower = hay_orig:lower()
	local total = 0
	for _, or_terms in ipairs(and_groups) do
		local best = 0
		local any_match = false
		for _, term in ipairs(or_terms) do
			local hay = term.ignorecase and hay_lower or hay_orig
			local s = score_term(hay, term.text, term.prefix, term.suffix, term.exact)
			if term.inverse then
				if s == 0 then
					best = math.max(best, 1)
					any_match = true
				end
			else
				if s > 0 then
					best = math.max(best, s)
					any_match = true
				end
			end
		end
		if not any_match then
			return 0
		end
		total = total + best
	end
	return total
end

---@param item Beast.Finder.Item
---@param filter Beast.Finder.Filter
---@param cfg {smartcase: boolean, ignorecase: boolean}
---@return number score 0 = no match
function M.score(item, filter, cfg)
	local groups = parse_pattern(filter.pattern, cfg.ignorecase, cfg.smartcase)
	return score_item(item, groups)
end

---@param items Beast.Finder.Item[]
---@param filter Beast.Finder.Filter
---@param cfg {smartcase: boolean, ignorecase: boolean}
---@param on_done fun(matched: Beast.Finder.Item[])
function M.run(items, filter, cfg, on_done)
	async.spawn(function()
		local groups = parse_pattern(filter.pattern, cfg.ignorecase, cfg.smartcase)
		local matched = {}
		local yield = async.yielder(1)
		for i = 1, #items do
			local item = items[i]
			local s = score_item(item, groups)
			item.score = s
			if s > 0 then
				matched[#matched + 1] = item
			end
			yield()
		end
		table.sort(matched, function(a, b)
			return a.score > b.score
		end)
		vim.schedule(function()
			on_done(matched)
		end)
	end)
end

return M
