local Score = require("beast.libs.finder.score")
local TopK = require("beast.libs.finder.topk")
local async = require("beast.libs.async")

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
---@field entropy number selectivity score for ordering

---@param raw string
---@param ignorecase boolean
---@param smartcase boolean
---@return Beast.Finder.Term[][]  AND-groups of OR-terms (sorted by max entropy, highest first)
local function parse_pattern(raw, ignorecase, smartcase)
	local and_groups = {} ---@type Beast.Finder.Term[][]
	for _, and_part in ipairs(vim.split(raw, "%s+", { trimempty = true })) do
		local or_terms = {} ---@type Beast.Finder.Term[]
		for _, or_part in ipairs(vim.split(and_part, "|", { plain = true, trimempty = true })) do
			local text = or_part
			local inverse, exact, prefix, suffix = false, false, false, false
			local entropy = 0
			if text:sub(1, 1) == "!" then
				inverse = true
				text = text:sub(2)
				entropy = entropy - 1
			end
			if text:sub(1, 1) == "^" then
				prefix = true
				text = text:sub(2)
				entropy = entropy + 20
			elseif text:sub(1, 1) == "'" then
				exact = true
				text = text:sub(2)
				entropy = entropy + 10
			end
			if text:sub(-1) == "$" then
				suffix = true
				text = text:sub(1, -2)
				entropy = entropy + 20
			end
			if text ~= "" then
				local ic = ignorecase
				if smartcase and text:match("%u") then
					ic = false
				end
				-- Entropy: length + rare chars + case sensitivity
				local rare_chars = #text:gsub("[%w%s]", "")
				entropy = entropy + math.min(#text, 20) + rare_chars * 2
				if not ic then
					entropy = entropy * 2
				end
				if ic then
					text = text:lower()
				end
				or_terms[#or_terms + 1] = {
					text = text,
					inverse = inverse,
					exact = exact,
					prefix = prefix,
					suffix = suffix,
					ignorecase = ic,
					entropy = entropy,
				}
			end
		end
		if #or_terms > 0 then
			and_groups[#and_groups + 1] = or_terms
		end
	end
	-- Sort AND-groups by max entropy (most selective first for faster rejection)
	if #and_groups > 1 then
		table.sort(and_groups, function(a, b)
			local max_a, max_b = 0, 0
			for _, t in ipairs(a) do
				if t.entropy > max_a then
					max_a = t.entropy
				end
			end
			for _, t in ipairs(b) do
				if t.entropy > max_b then
					max_b = t.entropy
				end
			end
			return max_a > max_b
		end)
	end
	return and_groups
end

-- ---------------------------------------------------------------------------
-- Scoring
-- ---------------------------------------------------------------------------

-- Shared scorer instance (reused across calls to avoid allocations)
local scorer = Score:new()

--- Forward scan: find all needle chars in order starting from `init_pos`.
--- Returns (from, to) of the match window, or nil if no match.
---@param hay string
---@param needle string
---@param init_pos? number 1-based start position (default 1)
---@return number? from, number? to
local function fuzzy_find(hay, needle, init_pos)
	local byte = string.byte
	local hlen = #hay
	local nlen = #needle
	local from = nil
	local ni = 1
	for hi = init_pos or 1, hlen do
		if byte(hay, hi) == byte(needle, ni) then
			if ni == 1 then
				from = hi
			end
			ni = ni + 1
			if ni > nlen then
				return from, hi
			end
		end
	end
	return nil, nil
end

--- Collect fuzzy match positions for highlighting (forward scan from `from`).
---@param hay string
---@param needle string
---@param from number start position
---@return integer[] positions
local function fuzzy_positions(hay, needle, from)
	local byte = string.byte
	local nlen = #needle
	local positions = {}
	local ni = 1
	for hi = from, #hay do
		if byte(hay, hi) == byte(needle, ni) then
			positions[#positions + 1] = hi
			ni = ni + 1
			if ni > nlen then
				break
			end
		end
	end
	return positions
end

---@param hay string lowercased (or original if case-sensitive)
---@param hay_orig string original case (for score char-class detection)
---@param needle string lowercased (or original if case-sensitive)
---@param prefix boolean
---@param suffix boolean
---@param exact boolean
---@return number score
---@return integer[]? positions
local function score_term(hay, hay_orig, needle, prefix, suffix, exact)
	local hlen = #hay
	local nlen = #needle

	-- stylua: ignore
	if nlen == 0 or nlen > hlen then return 0, nil end

	-- Exact / prefix / suffix: plain substring match
	if exact or prefix or suffix then
		local idx = hay:find(needle, 1, true)
		-- stylua: ignore
		if not idx then return 0, nil end
		-- stylua: ignore
		if prefix and idx ~= 1 then return 0, nil end
		-- stylua: ignore
		if suffix and idx + nlen - 1 ~= hlen then return 0, nil end

		local s = scorer:get(hay_orig, idx, idx + nlen - 1)
		local pos = {}
		for i = idx, idx + nlen - 1 do
			pos[#pos + 1] = i
		end
		return s, pos
	end

	-- Fuzzy: multi-start scan — try every valid start position, keep best
	local from, to = fuzzy_find(hay, needle, 1)
	-- stylua: ignore
	if not from then return 0, nil end

	-- Score first window
	scorer.is_file = true
	scorer:init(hay_orig, from)
	local ni = 2
	for hi = from + 1, to do
		if string.byte(hay, hi) == string.byte(needle, ni) then
			scorer:update(hi)
			ni = ni + 1
		end
	end
	local best_score = scorer.score
	local best_from = from

	-- Try subsequent start positions (capped at 10 attempts)
	local attempts = 1
	local next_from, next_to = fuzzy_find(hay, needle, from + 1)
	while next_from and attempts < 10 do
		attempts = attempts + 1
		scorer.is_file = true
		scorer:init(hay_orig, next_from)
		ni = 2
		for hi = next_from + 1, next_to do
			if string.byte(hay, hi) == string.byte(needle, ni) then
				scorer:update(hi)
				ni = ni + 1
			end
		end
		if scorer.score > best_score then
			best_score = scorer.score
			best_from = next_from
		end
		next_from, next_to = fuzzy_find(hay, needle, next_from + 1)
	end

	-- stylua: ignore
	if best_score <= 0 then return 0, nil end

	local positions = fuzzy_positions(hay, needle, best_from)
	return best_score, positions
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
			local s, pos = score_term(hay, hay_orig, term.text, term.prefix, term.suffix, term.exact)
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
---@param on_done fun(matched: Beast.Finder.Item[], state?: Beast.Finder.MatchState)
---@param prev_state? Beast.Finder.MatchState
---@param topk_capacity? integer defaults to 1000
function M.run(items, filter, cfg, on_done, prev_state, topk_capacity)
	return async.spawn(function()
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
		---@diagnostic disable-next-line: need-check-nil
		local prev_scores = use_subset and prev_state.scores or nil

		-- Progressive rendering: show partial results every ~16ms
		local uv = vim.uv or vim.loop
		local last_progress = uv.hrtime()
		local PROGRESS_NS = 16e6 -- 16ms (~60fps)

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

			-- Emit progressive results so the UI feels responsive
			if uv.hrtime() - last_progress > PROGRESS_NS then
				last_progress = uv.hrtime()
				local partial = topk:sorted()
				vim.schedule(function()
					on_done(partial, nil)
				end)
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
