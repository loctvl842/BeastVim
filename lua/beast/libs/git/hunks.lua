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

--- Translate staged hunk positions from INDEX line space to BUFFER line space.
---
--- Staged hunks come from `diff(head, base)` so:
---   - `a_*` are HEAD line numbers (irrelevant here)
---   - `b_*` are INDEX line numbers (what we need to translate)
---
--- The unstaged diff is `diff(base=index, buffer)` so its `a_*` is in
--- INDEX space and `b_*` in BUFFER space. Each unstaged hunk that ends
--- strictly before an INDEX position shifts it by `(b_count - a_count)`.
---
--- Hunks whose target buffer line is shadowed by an unstaged change at the
--- same line are still emitted — the higher-priority unstaged sign will
--- override them at render time.
---
---@param staged Beast.Git.RawHunk[]   Hunks in head→index space (b_* in INDEX space)
---@param unstaged Beast.Git.RawHunk[] Hunks in index→buffer space (a_* in INDEX space)
---@param n_lines integer              Buffer line count (for clipping)
---@return table<integer, { type: string }>
function M.expand_staged_signs(staged, unstaged, n_lines)
	local out = {}
	for i = 1, #staged do
		local h = staged[i]
		-- Anchor in INDEX space: b_start for add/change, b_start (or 0) for delete.
		local anchor_index = h.b_start
		local delta = 0
		for j = 1, #unstaged do
			local u = unstaged[j]
			-- End-exclusive index position of the unstaged hunk. Pure-adds
			-- (a_count=0) are insertions BETWEEN a_start and a_start+1, so
			-- they only shift lines strictly above a_start.
			local u_end = u.a_start + math.max(u.a_count, 1)
			if u_end <= anchor_index then
				delta = delta + (u.b_count - u.a_count)
			else
				break
			end
		end

		if h.type == "add" then
			local start = h.b_start + delta
			for ln = start, start + h.b_count - 1 do
				if ln >= 1 and ln <= n_lines then
					out[ln] = { type = "add" }
				end
			end
		elseif h.type == "delete" then
			if h.b_start == 0 then
				out[1] = { type = "topdelete" }
			else
				local ln = math.min(h.b_start + delta, n_lines)
				if ln >= 1 then
					out[ln] = { type = "delete" }
				end
			end
		else -- change
			local start = h.b_start + delta
			local last_changed = start + h.b_count - 1
			for ln = start, last_changed do
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

--- Compute INDEX→BUFFER shift for a single INDEX line, given the unstaged
--- diff that maps INDEX→BUFFER (its `a_*` is in INDEX space).
---
--- The shift includes every unstaged hunk that ends strictly before the
--- index position. See `expand_staged_signs` for the same end-exclusive
--- arithmetic and why pure-adds use `max(a_count, 1)`.
---@param index_line integer 1-based index-space line
---@param unstaged Beast.Git.RawHunk[]
---@return integer delta
function M.index_to_buffer_delta(index_line, unstaged)
	local delta = 0
	for i = 1, #unstaged do
		local u = unstaged[i]
		local u_end = u.a_start + math.max(u.a_count, 1)
		if u_end <= index_line then
			delta = delta + (u.b_count - u.a_count)
		else
			break
		end
	end
	return delta
end

--- Find a hunk that "covers" the given buffer line. A hunk covers a buffer
--- line when its rendered sign (see `expand_signs`) would land on that line.
---
--- - add/change: lines `b_start..b_start+b_count-1`
--- - delete:     a single line at `b_start` (1 if topdelete)
---
--- Returns the first match; hunks are presumed non-overlapping (true for
--- diff output).
---@param hunks Beast.Git.RawHunk[]
---@param lnum integer 1-based buffer line
---@return Beast.Git.RawHunk?
function M.find_at_buffer_line(hunks, lnum)
	for i = 1, #hunks do
		local h = hunks[i]
		if h.type == "delete" then
			local target = h.b_start == 0 and 1 or h.b_start
			if target == lnum then
				return h
			end
		else
			if lnum >= h.b_start and lnum <= h.b_start + h.b_count - 1 then
				return h
			end
		end
	end
	return nil
end

--- Find a staged hunk that covers the given buffer line, using the unstaged
--- diff to project its INDEX-space `b_*` into BUFFER space.
---@param staged Beast.Git.RawHunk[]
---@param unstaged Beast.Git.RawHunk[]
---@param lnum integer
---@return Beast.Git.RawHunk?
function M.find_staged_at_buffer_line(staged, unstaged, lnum)
	for i = 1, #staged do
		local h = staged[i]
		local delta = M.index_to_buffer_delta(h.b_start == 0 and 1 or h.b_start, unstaged)
		local buf_b_start = h.b_start + (h.b_start == 0 and 0 or delta)
		if h.type == "delete" then
			local target = buf_b_start == 0 and 1 or buf_b_start
			if target == lnum then
				return h
			end
		else
			if lnum >= buf_b_start and lnum <= buf_b_start + h.b_count - 1 then
				return h
			end
		end
	end
	return nil
end

--- Find all hunks whose BUFFER-side footprint intersects `[s, e]` inclusive.
--- Whole-hunk inclusion (matches gitsigns / mini.diff default range behaviour);
--- callers wanting partial-line stage must re-diff the clipped region.
---@param hunks Beast.Git.RawHunk[]
---@param s integer 1-based start line (inclusive)
---@param e integer 1-based end line (inclusive)
---@return Beast.Git.RawHunk[]
function M.find_in_range(hunks, s, e)
	if s > e then
		s, e = e, s
	end
	local out = {}
	for i = 1, #hunks do
		local h = hunks[i]
		local lo, hi
		if h.type == "delete" then
			lo = h.b_start == 0 and 1 or h.b_start
			hi = lo
		else
			lo = h.b_start
			hi = h.b_start + h.b_count - 1
		end
		if hi >= s and lo <= e then
			out[#out + 1] = h
		end
	end
	return out
end

return M
