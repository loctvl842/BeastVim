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
---@field help_tag? string
---@field is_readme? boolean
---@field _lower? string cached lowercased text for matcher

---@class Beast.Finder.Query
---@field items Beast.Finder.Item[]
---@field matched Beast.Finder.Item[]
---@field filter Beast.Finder.Filter
---@field source Beast.Finder.ASource
---@field highlight_preview boolean -- true for stream sources (grep) — highlights pattern in preview
local M = setmetatable({}, {
	__call = function(t, ...)
		return t:new(...)
	end,
})
M.__index = M

-- ---------------------------------------------------------------------------
-- Constructor / public methods
-- ---------------------------------------------------------------------------
---@class Beast.Finder.QueryOpts
---@field cwd? string
---@field lsp? {results: Beast.Finder.Item[], symbol?: string} pre-fetched LSP results

---@param source Beast.Finder.ASource
---@param opts? Beast.Finder.QueryOpts
---@return Beast.Finder.Query
function M:new(source, opts)
	opts = opts or {}

	local is_live = source and source.live or false

	local query = setmetatable({
		items = {},
		matched = {},
		filter = Filter({ cwd = opts.cwd, lsp = opts.lsp }),
		source = source,
		highlight_preview = is_live,
	}, self)

	return query
end

return M
