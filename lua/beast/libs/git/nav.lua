-- Hunk navigation.
--
-- nav_hunk("next" | "prev", { wrap, foldopen, target }) jumps the cursor
-- to the start of the closest hunk in the given direction.
--
-- `target` selects which tier(s) to consider:
--   "unstaged" (default) → like before, only live edits
--   "staged"             → only hunks already in the index
--   "all"                → both tiers, merged and sorted by buffer line
--
-- For "staged"/"all" we project the staged hunks' INDEX-space b_* into
-- BUFFER space via hunks.index_to_buffer_delta so jumps land on the
-- same line the staged sign was rendered on.

local api = vim.api

local M = {}

---@class Beast.Git.NavOpts
---@field wrap? boolean Wrap around at file boundaries (default true)
---@field foldopen? boolean Open folds at the target line (default true)
---@field target? "unstaged"|"staged"|"all" Which hunk tier to navigate (default "unstaged")

---@param hunk Beast.Git.RawHunk
---@return integer 1-based buffer line of the hunk's landing position
local function landing_line(hunk)
	if hunk.type == "delete" or hunk.b_start == 0 then
		return hunk.b_start == 0 and 1 or hunk.b_start
	end
	return hunk.b_start
end

---@param target "unstaged"|"staged"|"all"
---@return integer[] sorted buffer-line landing positions (deduped)
local function collect_landing_lines(target)
	local git = require("beast.libs.git")
	local hunks_mod = require("beast.libs.git.hunks")
	local unstaged = git.get_hunks()
	local staged = git.get_staged_hunks()

	local lines = {}
	if target == "unstaged" or target == "all" then
		for _, h in ipairs(unstaged) do
			lines[#lines + 1] = landing_line(h)
		end
	end
	if target == "staged" or target == "all" then
		for _, h in ipairs(staged) do
			local anchor = h.b_start == 0 and 1 or h.b_start
			local delta = hunks_mod.index_to_buffer_delta(anchor, unstaged)
			local projected = { b_start = h.b_start + (h.b_start == 0 and 0 or delta), type = h.type }
			lines[#lines + 1] = landing_line(projected)
		end
	end

	table.sort(lines)
	-- Dedup adjacent equals (staged + unstaged can collide at the same line).
	local out, prev = {}, nil
	for i = 1, #lines do
		if lines[i] ~= prev then
			out[#out + 1] = lines[i]
			prev = lines[i]
		end
	end
	return out
end

---@param direction "next" | "prev"
---@param opts? Beast.Git.NavOpts
function M.nav_hunk(direction, opts)
	opts = opts or {}
	local wrap = opts.wrap ~= false
	local foldopen = opts.foldopen ~= false
	local target = opts.target or "unstaged"

	local lines = collect_landing_lines(target)
	if #lines == 0 then
		return
	end

	local cursor = api.nvim_win_get_cursor(0)[1]
	local target_line

	if direction == "next" then
		for i = 1, #lines do
			if lines[i] > cursor then
				target_line = lines[i]
				break
			end
		end
		if not target_line and wrap then
			target_line = lines[1]
		end
	else
		for i = #lines, 1, -1 do
			if lines[i] < cursor then
				target_line = lines[i]
				break
			end
		end
		if not target_line and wrap then
			target_line = lines[#lines]
		end
	end

	if not target_line then
		return
	end

	-- Set the `''` mark so `g;` / `''` jump back to the pre-nav cursor.
	vim.cmd("normal! m'")
	api.nvim_win_set_cursor(0, { target_line, 0 })
	if foldopen then
		vim.cmd("normal! zv")
	end
end

return M
