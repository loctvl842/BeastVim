--- Reads a paginated list endpoint of a forge page by page, whichever CLI makes the request.
--- `PAGES` pages are kept; one more is read only to tell whether the list was cut short.

---@class Beast.Finder.Pager.Page
---@field list? table[] decoded page
---@field error? Beast.Finder.Gh.Error

---@class Beast.Finder.Pager.Result
---@field items? any[]
---@field truncated? boolean the list has more than `PAGES` pages
---@field error? Beast.Finder.Gh.Error

---@class Beast.Finder.Pager
local M = {}

M.PER_PAGE = 100
M.PAGES = 3

--- `run(page, done)` starts the request for one page and returns its process; `done` takes the decoded
--- list or an error. `cb` runs on the main loop, also after `kill()`; callers that cancel must ignore it.
---@generic T
---@param run fun(page: integer, done: fun(page: Beast.Finder.Pager.Page)): vim.SystemObj
---@param normalize fun(raw: table): T
---@param cb fun(result: Beast.Finder.Pager.Result)
---@return Beast.Finder.Gh.Handle
function M.collect(run, normalize, cb)
	local out, killed = {}, false
	local proc ---@type vim.SystemObj?

	local function fetch(page)
		proc = run(page, function(res)
			if res.error then
				return cb({ error = res.error })
			end
			local list = res.list ---@cast list table[]
			-- The page after the last one we keep only tells whether the list was cut short.
			if page > M.PAGES then
				return cb({ items = out, truncated = #list > 0 })
			end
			for _, raw in ipairs(list) do
				out[#out + 1] = normalize(raw)
			end
			if #list < M.PER_PAGE or killed then
				return cb({ items = out })
			end
			fetch(page + 1)
		end)
	end
	fetch(1)

	return {
		kill = function()
			killed = true
			if proc then
				pcall(proc.kill, proc, 15)
			end
		end,
	}
end

return M
