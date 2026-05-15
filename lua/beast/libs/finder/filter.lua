---@class Beast.Finder.Filter
---@field pattern string fuzzy pattern driving the matcher
---@field search string seed passed to live sources (e.g. grep term)
---@field cwd string normalized working directory
---@field buf? number restrict to buffer

local M = {}

---@param opts? {cwd?: string, buf?: number, search?: string}
---@return Beast.Finder.Filter
function M.new(opts)
	opts = opts or {}
	return {
		pattern = "",
		search = opts.search or "",
		cwd = opts.cwd or Util.root(),
		buf = opts.buf,
	}
end

---@param filter Beast.Finder.Filter
---@param pattern string
function M.update(filter, pattern)
	filter.pattern = pattern
end

return M
