local config = require("beast.libs.tabline.config")
local truncate = require("beast.libs.tabline.truncate")

local M = {}

local displaywidth = truncate.displaywidth

--- Compute the display width of the toggle button section.
---@return integer
function M.width()
	local icon = vim.o.background == "dark" and config.toggle_button_dark_icon or config.toggle_button_light_icon
	-- Renders as " <icon> " = 1 + icon_w + 1
	return 1 + displaywidth(icon) + 1
end

--- Render the toggle button section.
---@return string
function M.render()
	local icon = vim.o.background == "dark" and config.toggle_button_dark_icon or config.toggle_button_light_icon
	return "%@v:lua.beast_tabline_toggle_bg@%#BeastTlToggleButton# " .. icon .. " %X"
end

return M
