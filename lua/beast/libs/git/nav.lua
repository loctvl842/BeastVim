-- Hunk navigation.
--
-- nav_hunk("next" | "prev", { wrap = true, foldopen = true }) jumps the
-- cursor to the start of the closest hunk in the given direction. Source
-- of truth is `init.lua`'s state: M.get_hunks(buf) returns the same hunk
-- list the diff pipeline last computed.

local api = vim.api

local M = {}

---@class Beast.Git.NavOpts
---@field wrap? boolean Wrap around at file boundaries (default true)
---@field foldopen? boolean Open folds at the target line (default true)

---@param direction "next" | "prev"
---@param opts? Beast.Git.NavOpts
function M.nav_hunk(direction, opts)
	opts = opts or {}
	local wrap = opts.wrap ~= false
	local foldopen = opts.foldopen ~= false

	local git = require("beast.libs.git")
	local hunks = git.get_hunks()
	if #hunks == 0 then
		return
	end

	-- Sort by start line so direction logic is unambiguous. Diff already
	-- yields ascending order but we don't rely on that contract.
	table.sort(hunks, function(a, b)
		return (a.b_start == 0 and 1 or a.b_start) < (b.b_start == 0 and 1 or b.b_start)
	end)

	local cursor = api.nvim_win_get_cursor(0)[1]
	local target

	if direction == "next" then
		for _, h in ipairs(hunks) do
			local ln = h.b_start == 0 and 1 or h.b_start
			if ln > cursor then
				target = ln
				break
			end
		end
		if not target and wrap then
			local h = hunks[1]
			target = h.b_start == 0 and 1 or h.b_start
		end
	else
		for i = #hunks, 1, -1 do
			local h = hunks[i]
			local ln = h.b_start == 0 and 1 or h.b_start
			if ln < cursor then
				target = ln
				break
			end
		end
		if not target and wrap then
			local h = hunks[#hunks]
			target = h.b_start == 0 and 1 or h.b_start
		end
	end

	if not target then
		return
	end

	-- Set the `''` mark so `g;` / `''` jump back to the pre-nav cursor.
	vim.cmd("normal! m'")
	api.nvim_win_set_cursor(0, { target, 0 })
	if foldopen then
		vim.cmd("normal! zv")
	end
end

return M
