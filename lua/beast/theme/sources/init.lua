---@class Beast.Theme.Source
---@field name "beastvim"|"nvim"|"plugin"
---@field matches? fun(colors_name: string): boolean
---@field extract? fun(): Beast.Theme.Palette
---@field post_apply? fun(palette: Beast.Theme.Palette)

local M = {}

--- Ordered by precedence: first match wins, `plugin` is the fallback.
---@type Beast.Theme.Source[]
local sources = {
	require("beast.theme.sources.beastvim"),
	require("beast.theme.sources.nvim"),
	require("beast.theme.sources.plugin"),
}

--- Whether `<dir>/<name>.lua|vim` exists.
---@param dir string
---@param name string
---@return boolean
function M.colorscheme_exists(dir, name)
	local base = dir .. "/" .. name
	return vim.uv.fs_stat(base .. ".lua") ~= nil or vim.uv.fs_stat(base .. ".vim") ~= nil
end

--- Resolve the source for the active colorscheme.
---@return Beast.Theme.Source
function M.detect()
	local name = vim.g.colors_name or "default"
	for _, source in ipairs(sources) do
		if source.matches(name) then
			return source
		end
	end
	return sources[#sources]
end

return M
