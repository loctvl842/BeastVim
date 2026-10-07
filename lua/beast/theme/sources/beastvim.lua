--- Themes shipped in this config's `colors/` directory. They carry the palette
--- in `BeastVim*` highlight groups (fg = palette value).
local palette = require("beast.theme.palette")

---@type Beast.Theme.Source
local M = { name = "beastvim" }

---@param name string
---@return boolean
function M.matches(name)
	return require("beast.theme.sources").colorscheme_exists(vim.fn.stdpath("config") .. "/colors", name)
end

---@return Beast.Theme.Palette
function M.extract()
	local map = {}
	for key in pairs(palette.defaults) do
		map[key] = { "BeastVim" .. key:sub(1, 1):upper() .. key:sub(2), "fg" }
	end
	return palette.from_groups(map)
end

M.post_apply = palette.override_statusline

return M
