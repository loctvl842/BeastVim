local Query = require("beast.libs.finder.query")

local M = {}

local query ---@type Beast.Finder.Query

---@param opts? Beast.Finder.Config
function M.setup(opts)
	require("beast.libs.finder.config").setup(opts)
	require("beast.libs.finder.highlights")
end

---@param source Beast.Finder.Source
---@param opts? Beast.Finder.QueryOpts
function M.open(source, opts)
	if query then
		query:close()
	end
	query = Query(source, opts)
	query:load()
end

return M
