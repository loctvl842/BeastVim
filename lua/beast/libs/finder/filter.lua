---@class Beast.Finder.Filter
---@field pattern string fuzzy pattern driving the matcher
---@field search string seed passed to live sources (e.g. grep term)
---@field cwd string normalized working directory
---@field buf? number restrict to buffer
---@field lsp? {results: Beast.Finder.Item[], symbol?: string} pre-fetched LSP results
local M = setmetatable({}, {
	__call = function(t, ...)
		return t:new(...)
	end,
})
M.__index = M

---@param opts? {cwd?: string, buf?: number, search?: string, lsp?: {results: Beast.Finder.Item[], symbol?: string}}
---@return Beast.Finder.Filter
function M:new(opts)
	opts = opts or {}
	return setmetatable({
		pattern = "",
		search = opts.search or "",
		cwd = opts.cwd or Util.root(),
		buf = opts.buf,
		lsp = opts.lsp,
	}, self)
end

---@param pattern string
function M:update(pattern)
	self.pattern = pattern
end

return M
