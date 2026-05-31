-- Sign collection + classification.
--
-- Walks `nvim_buf_get_extmarks(buf, -1, 0, -1, { type = "sign", details = true })`
-- once per (win, tick) and bucketises the results into classes used by the
-- statuscolumn producers: "diagnostic", "git", "other".
--
-- Classification rules (first match wins):
--   1. Namespace pattern on the extmark's ns_id (resolved through
--      `nvim_get_namespaces`). Handles modern vim.diagnostic / gitsigns /
--      mini.diff extmarks which are unnamed at the sign level.
--   2. Sign name / hl_group pattern. Catches legacy `DiagnosticSign*`
--      and named gitsigns variants that older plugin versions still ship.
--
-- Within each class, the highest-priority sign per lnum wins. Ties resolved
-- in extmark order (first one to win sticks — extmarks are returned in
-- insertion order which is "close enough" deterministic for our needs).

local api = vim.api

local M = {}

---@class Beast.Statuscolumn.Sign
---@field text string  Display text (e.g. "E ", "▎", "")
---@field hl string    Highlight group (sign_hl_group)
---@field priority integer

---@alias Beast.Statuscolumn.SignClass "diagnostic"|"git"|"other"

-- Namespace patterns (matched with `string.find`, pattern-aware).
local NS_PATTERNS = {
	{ class = "diagnostic", pattern = "^vim%.diagnostic" },
	{ class = "git", pattern = "^beast_git_signs" },
	{ class = "git", pattern = "^gitsigns" },
}

-- Name / hl_group patterns (fallback when namespace doesn't match).
local NAME_PATTERNS = {
	{ class = "diagnostic", pattern = "^DiagnosticSign" },
	{ class = "diagnostic", pattern = "^DiagnosticVirtualText" },
	{ class = "git", pattern = "^GitSigns" },
	{ class = "git", pattern = "^MiniDiffSign" },
}

-- =========================================================================
-- Namespace id → name resolution (memoised)
-- =========================================================================

---@type table<integer, string>
local ns_name_cache = {}

---@param ns_id integer
---@return string
local function ns_name(ns_id)
	local cached = ns_name_cache[ns_id]
	if cached ~= nil then
		return cached
	end

	-- Cache miss: refresh the whole map. Namespaces are few (dozens) so this
	-- is cheap. Misses can become hits when plugins register namespaces
	-- lazily, so we never cache the empty-string "unknown" result.
	for name, id in pairs(api.nvim_get_namespaces()) do
		ns_name_cache[id] = name
	end

	return ns_name_cache[ns_id] or ""
end

-- =========================================================================
-- Classifier
-- =========================================================================

---@param ns_id integer
---@param name string
---@return Beast.Statuscolumn.SignClass
function M.classify(ns_id, name)
	if ns_id and ns_id > 0 then
		local nsname = ns_name(ns_id)
		if nsname ~= "" then
			for i = 1, #NS_PATTERNS do
				if nsname:find(NS_PATTERNS[i].pattern) then
					return NS_PATTERNS[i].class
				end
			end
		end
	end

	if name and name ~= "" then
		for i = 1, #NAME_PATTERNS do
			if name:find(NAME_PATTERNS[i].pattern) then
				return NAME_PATTERNS[i].class
			end
		end
	end

	return "other"
end

-- =========================================================================
-- Collection (one extmark walk per redraw)
-- =========================================================================

---@param buf integer
---@return table<Beast.Statuscolumn.SignClass, table<integer, Beast.Statuscolumn.Sign>>
function M.collect(buf)
	---@type table<Beast.Statuscolumn.SignClass, table<integer, Beast.Statuscolumn.Sign>>
	local out = { diagnostic = {}, git = {}, other = {} }

	local ok, extmarks = pcall(api.nvim_buf_get_extmarks, buf, -1, 0, -1, { type = "sign", details = true })
	if not ok then
		return out
	end

	for i = 1, #extmarks do
		local em = extmarks[i]
		local lnum = em[2] + 1
		local d = em[4]
		local text = d.sign_text
		if text and text ~= "" then
			local name = d.sign_hl_group or d.sign_name or ""
			local class = M.classify(d.ns_id or 0, name)
			local prio = d.priority or 0
			local bucket = out[class]
			local existing = bucket[lnum]
			if not existing or prio > existing.priority then
				bucket[lnum] = {
					text = text,
					hl = d.sign_hl_group or "",
					priority = prio,
				}
			end
		end
	end

	return out
end

--- Reset memoised namespace map (for tests).
function M._reset_cache()
	ns_name_cache = {}
end

return M
