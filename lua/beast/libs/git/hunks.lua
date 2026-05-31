-- Hunk → per-line sign expansion.
--
-- expand_signs(hunks, n_buffer_lines) returns:
--   { [lnum] = { type = "add" | "change" | "delete" | "topdelete" | "changedelete" } }
--
-- Rules (matching gitsigns/calc_signs):
--   pure add        →  "add" on each b_start..b_start+b_count-1
--   pure delete     →  "topdelete" on line 1 if b_start == 0,
--                       else "delete" on b_start
--   change          →  "change" on each b_start..b_start+b_count-1.
--                       If a_count > b_count, the LAST changed line becomes
--                       "changedelete" (indicating dropped trailing lines).

local M = {}

---@param hunks Beast.Git.RawHunk[]
---@param n_lines integer Number of lines in the current buffer.
---@return table<integer, { type: string }>
function M.expand_signs(hunks, n_lines)
	local out = {}
	for i = 1, #hunks do
		local h = hunks[i]
		if h.type == "add" then
			for ln = h.b_start, h.b_start + h.b_count - 1 do
				if ln >= 1 and ln <= n_lines then
					out[ln] = { type = "add" }
				end
			end
		elseif h.type == "delete" then
			if h.b_start == 0 then
				out[1] = { type = "topdelete" }
			else
				local ln = math.min(h.b_start, n_lines)
				if ln >= 1 then
					out[ln] = { type = "delete" }
				end
			end
		else -- change
			local last_changed = h.b_start + h.b_count - 1
			for ln = h.b_start, last_changed do
				if ln >= 1 and ln <= n_lines then
					out[ln] = { type = "change" }
				end
			end
			if h.a_count > h.b_count and last_changed >= 1 and last_changed <= n_lines then
				out[last_changed] = { type = "changedelete" }
			end
		end
	end
	return out
end

return M
