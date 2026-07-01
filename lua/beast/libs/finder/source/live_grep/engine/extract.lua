-- Bigram extraction from an `rg` regex query.
--
-- rg matches by regex, so a query like `require\(` searches for `require(`, and
-- `a.b` matches `axb`. We may only derive bigrams from literal runs, never from
-- bytes that the regex engine treats specially. Metacharacters split runs; a
-- backslash escapes (and we skip) the next byte so escaped metachars are not
-- mistaken for literals. Runs shorter than 2 bytes yield nothing.
--
-- An empty result means "cannot prefilter" — the caller must fall back to a full
-- scan. That keeps correctness: bigrams only ever narrow, rg always verifies.

local bigram = require("beast.libs.finder.source.live_grep.engine.bigram")

local M = {}

-- Bytes that break a literal run (rg/Rust regex metacharacters).
local META = {}
for ch in ("\\.|?*+()[]{}^$"):gmatch(".") do
	META[ch:byte()] = true
end

--- Maximal literal runs in a regex query (escaped/meta bytes excluded).
---@param query string
---@return string[]
function M.literal_runs(query)
	local runs, buf = {}, {}
	local i, n = 1, #query
	while i <= n do
		local b = query:byte(i)
		if b == 92 then -- backslash: skip it and the escaped byte
			i = i + 2
			if #buf > 0 then
				runs[#runs + 1] = table.concat(buf)
				buf = {}
			end
		elseif META[b] then
			if #buf > 0 then
				runs[#runs + 1] = table.concat(buf)
				buf = {}
			end
			i = i + 1
		else
			buf[#buf + 1] = string.char(b)
			i = i + 1
		end
	end
	if #buf > 0 then
		runs[#runs + 1] = table.concat(buf)
	end
	return runs
end

--- Deduplicated bigram keys from the query's literal runs. Empty = no prefilter.
---@param query string
---@return integer[]
function M.keys(query)
	local seen, keys = {}, {}
	for _, run in ipairs(M.literal_runs(query)) do
		for _, k in ipairs(bigram.keys_of(run)) do
			if not seen[k] then
				seen[k] = true
				keys[#keys + 1] = k
			end
		end
	end
	return keys
end

return M
