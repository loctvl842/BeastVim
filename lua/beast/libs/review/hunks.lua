-- Pure hunk computation: buffer lines vs proposed lines. No UI, no state.
--
-- Every hunk is normalised to "replace buffer rows [row, row + old_count) with
-- `new`", so pure insertions (old_count == 0) and pure deletions (new == {})
-- need no special casing by callers.

local M = {}

local diff_fn = (vim.text and vim.text.diff) or vim.diff

---@class Beast.Review.Hunk
---@field row integer       0-based first buffer row replaced (insert point when old_count == 0)
---@field old_count integer number of buffer rows replaced
---@field old string[]      current text of those rows
---@field new string[]      proposed replacement lines

---@class Beast.Review.Proposal
---@field lines string[]
---@field eol boolean   proposal ended with a newline
---@field crlf boolean  proposal used CRLF line endings

--- Split proposed file contents into lines.
--- A single trailing newline is a terminator, not an extra empty line.
---@param text string
---@return Beast.Review.Proposal
function M.split(text)
	local crlf = text:find("\r\n", 1, true) ~= nil
	local eol = text:sub(-1) == "\n"
	local lines = {}
	if text ~= "" then
		local body = eol and text:sub(1, -2) or text
		lines = vim.split(body, "\n", { plain = true })
		if crlf then
			for i, l in ipairs(lines) do
				lines[i] = l:gsub("\r$", "")
			end
		end
	end
	return { lines = lines, eol = eol, crlf = crlf }
end

---@param lines string[]
---@return string
local function join(lines)
	-- An empty list must stay "" (not "\n") or the diff sees one empty line.
	if #lines == 0 then
		return ""
	end
	return table.concat(lines, "\n") .. "\n"
end

--- Diff `old` against `new`.
---@param old string[]  current buffer lines
---@param new string[]  proposed lines
---@return Beast.Review.Hunk[]
function M.compute(old, new)
	local raw = diff_fn(join(old), join(new), { result_type = "indices" })
	local hunks = {}
	for _, r in ipairs(raw) do
		local a_start, a_count, b_start, b_count = r[1], r[2], r[3], r[4]
		-- count == 0 means "after line N" (N == 0: before the first line);
		-- count > 0 means 1-based first line.
		local row = a_count == 0 and a_start or a_start - 1
		local b_row = b_count == 0 and b_start or b_start - 1
		hunks[#hunks + 1] = {
			row = row,
			old_count = a_count,
			old = vim.list_slice(old, row + 1, row + a_count),
			new = vim.list_slice(new, b_row + 1, b_row + b_count),
		}
	end
	return hunks
end

return M
