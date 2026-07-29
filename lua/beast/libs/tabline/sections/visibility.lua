local config = require("beast.libs.tabline.config")
local truncate = require("beast.libs.tabline.truncate")
local visibility = require("beast.visibility")

local M = {}

local displaywidth = truncate.displaywidth

---@param icon string
---@return integer
local function cell_width(icon)
	-- Renders as " <icon> " = 1 + icon_w + 1
	return 1 + displaywidth(icon) + 1
end

---@param icon string
---@param on boolean
---@param click_fn string  global click-handler function name (v:lua.<name>)
---@return string
local function cell(icon, on, click_fn)
	local hl = on and "BeastTlVisibilityOn" or "BeastTlVisibilityOff"
	return "%@v:lua." .. click_fn .. "@%#" .. hl .. "# " .. icon .. " %X"
end

--- Compute the display width of the visibility toggle buttons section.
---@return integer
function M.width()
	return cell_width(config.visibility_hidden_icon) + cell_width(config.visibility_gitignored_icon)
end

--- Render the visibility toggle buttons section (hidden files, gitignored files).
---@return string
function M.render()
	return cell(config.visibility_hidden_icon, visibility.hidden, "beast_tabline_toggle_hidden")
		.. cell(config.visibility_gitignored_icon, visibility.gitignored, "beast_tabline_toggle_gitignored")
end

return M
