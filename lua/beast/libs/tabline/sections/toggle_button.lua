local config = require("beast.libs.tabline.config")
local truncate = require("beast.libs.tabline.truncate")

local M = {}

local displaywidth = truncate.displaywidth

--- Compute the display width of the toggle button section.
---@param compact? boolean Icon-only, no label (used when buffer list would overflow)
---@return integer
function M.width(compact)
	local icon = vim.o.background == "dark" and config.toggle_button_dark_icon or config.toggle_button_light_icon
	-- Renders as " <icon> " = 1 + icon_w + 1, or " <icon> <label> " with a label
	local w = 1 + displaywidth(icon) + 1
	if compact then
		return w
	end
	return w + displaywidth(config.toggle_button_label) + 1
end

--- Render the toggle button section.
---@param compact? boolean Icon-only, no label (used when buffer list would overflow)
---@return string
function M.render(compact)
	local icon = vim.o.background == "dark" and config.toggle_button_dark_icon or config.toggle_button_light_icon
	if compact then
		return "%@v:lua.beast_tabline_toggle_bg@%#BeastTlToggleButton# " .. icon .. " %X"
	end
	return "%@v:lua.beast_tabline_toggle_bg@%#BeastTlToggleButton# " .. icon .. " " .. config.toggle_button_label .. " %X"
end

return M
