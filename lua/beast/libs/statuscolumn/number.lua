-- Number producer.
--
-- Returns the number-segment string for one line. Mirrors Neovim's built-in
-- number column behaviour without a `mode` knob:
--
--   nu=off rnu=off  → blank
--   nu=on  rnu=off  → absolute (v:lnum)
--   nu=off rnu=on   → relative (v:relnum), 0 on cursor row
--   nu=on  rnu=on   → relative everywhere, absolute on the cursor row
--                     (the "hybrid" pattern)
--
-- Virtual / wrapped continuation lines (virtnum ~= 0) get "%=" so the column
-- right-aligns blank rather than repeating the number on wrap.

local wo = vim.wo

local M = {}

---@param win integer
---@param lnum integer
---@param relnum integer
---@param virtnum integer
---@return string
function M.format(win, lnum, relnum, virtnum)
	if virtnum ~= 0 then
		return "%="
	end

	local wopt = wo[win]
	local nu, rnu = wopt.number, wopt.relativenumber

	if not nu and not rnu then
		return ""
	end

	local n
	if rnu and (not nu or relnum ~= 0) then
		n = relnum
	else
		n = lnum
	end

	return "%=" .. n .. " "
end

return M
