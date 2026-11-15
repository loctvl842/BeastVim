---@class Beast.Finder.Filter
---@field pattern string fuzzy pattern driving the matcher
---@field search string seed passed to live sources (e.g. grep term)
---@field cwd string normalized working directory
---@field cur_win integer current window
---@field buf? number restrict to buffer
---@field files? string[] live sources: search only inside these files (absolute paths)
---@field ctx? table what a source needs from the level it was opened from
local M = setmetatable({}, {
	__call = function(t, ...)
		return t:new(...)
	end,
})
M.__index = M

---@param opts? {cwd?: string, buf?: number, search?: string, files?: string[], ctx?: table}
---@return Beast.Finder.Filter
function M:new(opts)
	opts = opts or {}
	return setmetatable({
		pattern = "",
		search = opts.search or "",
		cwd = opts.cwd or Util.root(),
		cur_win = vim.api.nvim_get_current_win(),
		buf = opts.buf,
		files = opts.files,
		ctx = opts.ctx,
	}, self)
end

---@param pattern string
function M:update(pattern)
	self.pattern = pattern
end

return M
