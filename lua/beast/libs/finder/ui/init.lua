---@class Beast.Finder.UI
---@field backdrop Beast.Finder.UI.Backdrop
---@field input Beast.Finder.UI.Input
---@field list Beast.Finder.UI.List
---@field preview Beast.Finder.UI.Preview
local M = {}

setmetatable(M, {
	__index = function(_, k)
		local mod = require("beast.libs.finder.ui." .. k)
		return mod
	end,
})

return M
