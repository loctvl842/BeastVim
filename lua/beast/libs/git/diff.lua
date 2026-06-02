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

return M
