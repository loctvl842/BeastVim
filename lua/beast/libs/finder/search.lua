--- Headless file search: streams the `files` source once, then re-scores the
--- cached items per query with the finder matcher. No windows, no picker State,
--- so other libs (explorer) can reuse the finder's search without its UI.
local Filter = require("beast.libs.finder.filter")
local config = require("beast.libs.finder.config")
local matcher = require("beast.libs.finder.matcher")

---@class Beast.Finder.Search
local M = {}

---@class Beast.Finder.Search.Result
---@field capped boolean more matches existed than `limit`
---@field loading boolean the source is still streaming items

---@class Beast.Finder.Search.Session
---@field cwd string
---@field limit integer
---@field items Beast.Finder.Item[]
---@field loading boolean
---@field filter Beast.Finder.Filter
---@field private gen integer bumped on refresh/close; stale source/matcher callbacks compare against it
---@field private cb? fun(matched: Beast.Finder.Item[], result: Beast.Finder.Search.Result)
---@field private task? Beast.Async.Task
---@field private match_state? Beast.Finder.MatchState
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
	local self = setmetatable({
		cwd = opts.cwd,
		limit = opts.limit or 1000,
		items = {},
		loading = false,
		filter = Filter({ cwd = opts.cwd }),
		gen = 0,
	}, Session)
	self:_load()
	return self
end

function Session:_load()
	self.gen = self.gen + 1
	local gen = self.gen
	self.items = {}
	self.match_state = nil
	self.loading = true

	require("beast.libs.finder.source").files.get(Filter({ cwd = self.cwd }), function(item)
		-- stylua: ignore
		if gen ~= self.gen then return end
		if item == nil then
			self.loading = false
			-- Items that arrived after the last query were never scored.
			self:_run()
			return
		end
		self.items[#self.items + 1] = item
	end)
end

function Session:_run()
	-- stylua: ignore
	if not self.cb then return end
	if self.task then
		self.task:abort()
	end

	local gen, cb = self.gen, self.cb
	self.task = matcher.run(self.items, self.filter, config.matcher, function(matched, state)
		-- Progressive partials carry no state; only the final result is reported.
		-- An aborted run can still deliver the result it had already queued; drop
		-- it when a newer query has changed the pattern since.
		-- stylua: ignore
		if not state or gen ~= self.gen or cb ~= self.cb or state.pattern ~= self.filter.pattern then return end
		self.match_state = state
		-- One slot beyond `limit` tells "exactly limit matches" from "more than limit".
		local capped = #matched > self.limit
		if capped then
			matched[#matched] = nil
		end
		cb(matched, { capped = capped, loading = self.loading })
	end, self.match_state, self.limit + 1)
end

--- Match `pattern` against the files found so far (and again once streaming ends).
---@param pattern string finder fuzzy syntax
---@param cb fun(matched: Beast.Finder.Item[], result: Beast.Finder.Search.Result)
function Session:query(pattern, cb)
	self.filter:update(pattern)
	self.cb = cb
	self:_run()
end

--- Re-read the file list (e.g. hidden/gitignored visibility changed). The last
--- query is re-run once the new list has streamed in.
function Session:refresh()
	if self.task then
		self.task:abort()
		self.task = nil
	end
	self:_load()
end

function Session:close()
	self.gen = self.gen + 1
	self.cb = nil
	if self.task then
		self.task:abort()
		self.task = nil
	end
end

return M
