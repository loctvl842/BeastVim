-- Braille frame set shared with finder/ui/input.lua's picker spinner, for
-- visual consistency between the two spinners the user may see back to back.
local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local FRAME_INTERVAL_MS = 80

---Time-derived frame index — no per-component timer/counter state needed;
---finder/status.lua already owns the repaint-triggering timer.
---@return string
local function spinner()
	local ms = math.floor(vim.uv.hrtime() / 1e6)
	local idx = math.floor(ms / FRAME_INTERVAL_MS) % #frames + 1
	return frames[idx]
end

---@type Beast.Statusline.ComponentSpec
return {
	update = { "User BeastFinderStatusChanged" },
	scope = "global",
	priority = 96,
	provider = function()
		local action = require("beast.libs.finder.status").action
		-- stylua: ignore
		if not action then return {} end
		return {
			{ text = spinner() .. " ", hl = { fg = "accent4" } },
			{ text = action .. "…", hl = { fg = "text" } },
		}
	end,
}
