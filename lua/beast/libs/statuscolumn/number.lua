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
-- Number is right-aligned to `numberwidth - 1` cells with a trailing space,
-- so the digit column stays put no matter what segments come after it.
-- Virtual / wrapped continuation lines (virtnum ~= 0) emit blank padding of
-- the same width so the column does not jump on wrapped rows.

local wo = vim.wo

local M = {}

---@param s string
---@param width integer
---@return string
local function right_pad(s, width)
	local need = width - #s
	if need <= 0 then
		return s
	end
	return (" "):rep(need) .. s
end

---@param win integer
---@param lnum integer
---@param relnum integer
---@param virtnum integer
---@return string
function M.format(win, lnum, relnum, virtnum)
	local wopt = wo[win]
	local nu, rnu = wopt.number, wopt.relativenumber
	if not nu and not rnu then
		return ""
	end

	local nw = wopt.numberwidth
	if not nw or nw < 1 then
		nw = 4
	end
	local digit_w = nw - 1

	if virtnum ~= 0 then
		return (" "):rep(nw)
	end

	local n
	if rnu and (not nu or relnum ~= 0) then
		n = relnum
	else
		n = lnum
	end

	return right_pad(tostring(n), digit_w) .. " "
end

return M
