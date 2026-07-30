local config = require("beast.libs.tabline.config")
local truncate = require("beast.libs.tabline.truncate")
local visibility = require("beast.visibility")

local M = {}

local displaywidth = truncate.displaywidth

---@param icon string
---@param label string
---@param compact? boolean Icon-only, no label (used when buffer list would overflow)
---@return integer
local function cell_width(icon, label, compact)
	-- Renders as " <icon> " = 1 + icon_w + 1, or " <icon> <label> " with a label
	local w = 1 + displaywidth(icon) + 1
	if compact then
		return w
	end
	return w + displaywidth(label) + 1
end

---@param icon string
---@param label string
---@param on boolean
---@param click_fn string  global click-handler function name (v:lua.<name>)
---@param compact? boolean Icon-only, no label (used when buffer list would overflow)
---@return string
local function cell(icon, label, on, click_fn, compact)
	local icon_hl = on and "BeastTlVisibilityOn" or "BeastTlVisibilityOff"
	if compact then
		return "%@v:lua." .. click_fn .. "@%#" .. icon_hl .. "# " .. icon .. " %X"
	end
	return "%@v:lua." .. click_fn .. "@%#" .. icon_hl .. "# " .. icon .. " %#BeastTlVisibilityLabel#" .. label .. " %X"
end

--- Compute the display width of the visibility toggle buttons section.
---@param compact? boolean Icon-only, no label (used when buffer list would overflow)
---@return integer
function M.width(compact)
	return cell_width(config.visibility_hidden_icon, config.visibility_hidden_label, compact)
		+ cell_width(config.visibility_gitignored_icon, config.visibility_gitignored_label, compact)
end

--- Render the visibility toggle buttons section (hidden files, gitignored files).
---@param compact? boolean Icon-only, no label (used when buffer list would overflow)
---@return string
function M.render(compact)
	return cell(config.visibility_hidden_icon, config.visibility_hidden_label, visibility.hidden, "beast_tabline_toggle_hidden", compact)
		.. cell(config.visibility_gitignored_icon, config.visibility_gitignored_label, visibility.gitignored, "beast_tabline_toggle_gitignored", compact)
end

return M
