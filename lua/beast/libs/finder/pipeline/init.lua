---@class Beast.Finder.Pipeline
---@field match Beast.Finder.Pipeline.Match
---@field stream Beast.Finder.Pipeline.Stream
local M = {}

setmetatable(M, {
	__index = function(_, k)
		local mod = require("beast.libs.finder.pipeline." .. k)
		return mod
	end,
})

return M
