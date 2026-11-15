--- Headless file search: streams the `files` source once, then re-scores the cached items per
--- query with the finder's match pipeline. No windows, no picker Session, so other libs
--- (explorer) can reuse the finder's search without its UI. It is the same engine the picker
--- runs, driven through a headless host.
---
--- Lives in the finder because it drives finder internals (Query, match pipeline, source.files);
--- callers only see `available()` and `files()`.
--- Currently only the explorer (search mode) uses it.
local Query = require("beast.libs.finder.query")
local host_mod = require("beast.libs.finder.host")
local match = require("beast.libs.finder.pipeline.match")

---@class Beast.Finder.Search
local M = {}

---@class Beast.Finder.Search.Result
---@field capped boolean more matches existed than `limit`
---@field loading boolean the source is still streaming items

---@class Beast.Finder.Search.Session
---@field cwd string
---@field limit integer
---@field loading boolean
---@field private q Beast.Finder.Query
---@field private host Beast.Finder.Host
---@field private closed boolean
---@field private cb? fun(matched: Beast.Finder.Item[], result: Beast.Finder.Search.Result)
local Session = {}
Session.__index = Session

---@return boolean
function M.available()
	local ok, files = pcall(require, "beast.libs.finder.source.files")
	return ok and files.supported()
end

---@param opts { cwd: string, limit?: integer }
---@return Beast.Finder.Search.Session
function M.files(opts)
	local limit = opts.limit or 1000
	-- One slot beyond `limit` tells "exactly limit matches" from "more than limit".
	local query = Query(require("beast.libs.finder.source").files, { cwd = opts.cwd, limit = limit + 1 })
	local self = setmetatable({
		cwd = opts.cwd,
		limit = limit,
		loading = true,
		q = query,
		closed = false,
	}, Session)
	self.host = host_mod.headless({
		alive = function()
			return not self.closed
		end,
		render = function()
			self:_report()
		end,
	})
	match.start(query, self.host)
	return self
end

--- Tell the caller about the scored result, once the scorer has finished (progressive partials are not reported).
function Session:_report()
	self.loading = self.q.loading
	-- stylua: ignore
	if not self.cb or self.q.matching then return end
	local matched = self.q.matched
	local capped = #matched > self.limit
	if capped then
		matched = vim.list_slice(matched, 1, self.limit)
	end
	self.cb(matched, { capped = capped, loading = self.loading })
end

--- Match `pattern` against the files found so far (and again once streaming ends).
---@param pattern string finder fuzzy syntax
---@param cb fun(matched: Beast.Finder.Item[], result: Beast.Finder.Search.Result)
function Session:query(pattern, cb)
	self.q.filter:update(pattern)
	self.cb = cb
	match.run(self.q, self.host)
end

--- Re-read the file list (e.g. hidden/gitignored visibility changed). The last
--- query is re-run once the new list has streamed in.
function Session:refresh()
	self.loading = true
	match.reload(self.q, self.host)
end

function Session:close()
	self.closed = true
	self.cb = nil
	match.abort(self.q)
end

return M
