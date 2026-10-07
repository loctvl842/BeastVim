---@class Beast.Theme.Palette
---@field dark2 string
---@field dark1 string
---@field background string
---@field text string
---@field accent1 string
---@field accent2 string
---@field accent3 string
---@field accent4 string
---@field accent5 string
---@field accent6 string
---@field dimmed1 string
---@field dimmed2 string
---@field dimmed3 string
---@field dimmed4 string
---@field dimmed5 string

local M = {}

---@type Beast.Theme.Palette
M.defaults = {
	dark2 = "#33353a",
	dark1 = "#282a30",
	background = "#14161b",
	text = "#e0e2ea",
	accent1 = "#ffc0b9",
	accent2 = "#fce094",
	accent3 = "#b3f6c0",
	accent4 = "#8cf8f7",
	accent5 = "#a6dbff",
	accent6 = "#ffcaff",
	dimmed1 = "#adafb6",
	dimmed2 = "#84868d",
	dimmed3 = "#66686e",
	dimmed4 = "#47494f",
	dimmed5 = "#282a30",
}

--- Read `attr` of highlight `group`, falling back when it is unset.
---@param group string
---@param attr "fg"|"bg"
---@param fallback string
---@return string
function M.extract(group, attr, fallback)
	return Util.colors.inspect(group)[attr] or fallback
end

--- Build a palette from a `{ key = { group, attr } }` map.
---@param map table<string, { [1]: string, [2]: "fg"|"bg" }>
---@return Beast.Theme.Palette
function M.from_groups(map)
	local palette = {}
	for key, default in pairs(M.defaults) do
		local spec = map[key]
		palette[key] = M.extract(spec[1], spec[2], default)
	end
	return palette
end

--- Nvim/beastvim themes often define StatusLine with reverse or a light bg
--- which clashes with the dark-themed UI. Override with palette-derived colors.
---@param p Beast.Theme.Palette
function M.override_statusline(p)
	vim.api.nvim_set_hl(0, "StatusLine", { fg = p.text, bg = p.dark2 })
	vim.api.nvim_set_hl(0, "StatusLineNC", { fg = p.dimmed3, bg = p.dark1 })
end

return M
