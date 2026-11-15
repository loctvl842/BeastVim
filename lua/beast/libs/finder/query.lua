local Filter = require("beast.libs.finder.filter")

---@class Beast.Finder.Item
---@field idx number
---@field score number
---@field text string
---@field cwd? string
---@field file? string
---@field buf? number
---@field positions? number[]
---@field pos? {[1]: number, [2]: number}
---@field end_pos? {[1]: number, [2]: number}
---@field grep_text? string
---@field match_text? string  literal text grep actually matched (for preview highlight)
---@field issue? Beast.Finder.Gh.Item issue grep: the issue the line was found in
---@field url? string web address (GitHub sources); Enter opens it, copy copies it
---@field message? boolean informational row (empty result, error); not an actionable item
---@field is_error? boolean message rows only: draw in the error color
---@field help_tag? string
---@field is_readme? boolean
---@field swatches? (string|false)[] colorschemes: ten hex colors in role order, nil until computed
---@field _lower? string cached lowercased text for matcher

---@class Beast.Finder.Query
---@field items Beast.Finder.Item[]
---@field matched Beast.Finder.Item[]
---@field filter Beast.Finder.Filter
---@field source Beast.Finder.ASource
---@field limit integer how many matches `matched` keeps (best first); the match pipeline's TopK capacity
---@field loading boolean the source is still delivering items
---@field matching boolean the scorer is still running over the items
---@field total integer how many items match the pattern (`matched` holds at most `limit` of them)
local M = setmetatable({}, {
	__call = function(t, ...)
		return t:new(...)
	end,
})
M.__index = M

M.DEFAULT_LIMIT = 1000

-- ---------------------------------------------------------------------------
-- Constructor / public methods
-- ---------------------------------------------------------------------------
---@class Beast.Finder.QueryOpts
---@field cwd? string
---@field preloaded_items? Beast.Finder.Item[]  Already-fetched items (e.g. from finder/preflight.lua); skips the source re-fetch in pipeline/match.lua
---@field limit? integer defaults to `M.DEFAULT_LIMIT`
---@field files? string[] live sources: search only inside these files
---@field ctx? table what a source needs from the level it was opened from

---@param source Beast.Finder.ASource
---@param opts? Beast.Finder.QueryOpts
---@return Beast.Finder.Query
function M:new(source, opts)
	opts = opts or {}

	local query = setmetatable({
		items = opts.preloaded_items or {},
		matched = {},
		filter = Filter({ cwd = opts.cwd, files = opts.files, ctx = opts.ctx }),
		source = source,
		limit = opts.limit or M.DEFAULT_LIMIT,
		loading = false,
		matching = false,
		total = 0,
	}, self)

	return query
end

return M
