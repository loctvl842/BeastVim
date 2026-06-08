---@class Beast.Finder.ASource
---@field live boolean
---@field async boolean
---@field get fun(filter: Beast.Finder.Filter, cb: fun(item: Beast.Finder.Item|nil))
---@field cmd? string
---@field args? string[]
---@field cancel? fun()

---@alias Beast.Finder.Source "files"|"buffers"|"live_grep"|"colorschemes"|"help_tags"|"lsp_definitions"|"lsp_references"|"lsp_declarations"|"lsp_implementations"

---@class Beast.Finder.SourceRegistry
---@field [Beast.Finder.Source] Beast.Finder.ASource
local M = {}

setmetatable(M, {
	__index = function(_, k)
		local mod = require("beast.libs.finder.source." .. k)
		return mod
	end,
})

return M
