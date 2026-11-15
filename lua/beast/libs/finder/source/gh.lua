--- Factory for the GitHub sources (`gh_pr`, `gh_issue`): the prompt text is a GitHub search query,
--- run through `gh api` and fed to the live (stream) pipeline.
local api = require("beast.libs.finder.source.gh.api")
local query = require("beast.libs.finder.source.gh.query")

---@class Beast.Finder.Source.Gh
local M = {}

local TITLES = { pr = "Pull Requests", issue = "Issues" }

--- A row that explains the list instead of being an item.
---@param text string
---@param is_error? boolean
---@return Beast.Finder.Item
local function message(text, is_error)
	return { idx = 1, score = 1, text = text, message = true, is_error = is_error }
end

---@param kind Beast.Finder.Gh.Kind
---@return Beast.Finder.ASource
function M.create(kind)
	local repo ---@type Beast.Finder.Gh.Repo? set by check(), which always runs before a picker opens
	local generation = 0 -- bumped on every search and cancel; late responses of older ones are dropped
	local handle ---@type Beast.Finder.Gh.Handle?
	local total = 0 -- matches GitHub reported for the last finished search
	local failed = false -- the last search errored, so there is no count to show

	local function stop()
		generation = generation + 1
		if handle then
			handle.kill()
			handle = nil
		end
	end

	local source = {
		live = true,
		async = true,
		auto_select = false,
		retain_results = true,
		run_when_empty = true,
		-- GitHub search allows 30 requests a minute: wait for typing to pause.
		debounce_ms = 400,
		initial_query = query.default_text(kind),
		cancel = stop,
		format = require("beast.libs.finder.format").gh,
	}

	source.preview = function(view, item)
		require("beast.libs.finder.source.gh.preview").show(view, item)
	end

	function source.check()
		local found, err = api.check(Util.root())
		if not found then
			Toast(err, vim.log.levels.WARN)
			return false
		end
		repo = found
		return true
	end

	function source.title(filter)
		local scope = repo and query.scope(filter and filter.pattern or source.initial_query, repo.slug) or ""
		return ("%s - %s"):format(TITLES[kind], scope)
	end

	function source.get(filter, cb)
		stop()
		local mine = generation
		---@cast repo Beast.Finder.Gh.Repo
		handle = api.search(query.build(filter.pattern, repo.slug), repo.host, function(result)
			-- stylua: ignore
			if mine ~= generation then return end
			handle = nil
			total = 0
			failed = result.error ~= nil
			if result.error then
				cb(message("GitHub could not run this search:", true))
				cb(message(result.error.message, true))
			elseif #result.items == 0 then
				cb(message("No results for this search"))
			else
				total = result.total or #result.items
				for i, item in ipairs(result.items) do
					item.idx = i
					item.score = 1
					cb(item)
				end
			end
			cb(nil)
		end)
	end

	function source.count(items)
		-- stylua: ignore
		if failed then return "" end
		local n = 0
		for _, item in ipairs(items) do
			if not item.message then
				n = n + 1
			end
		end
		return total > n and (n .. "+") or ("%d/%d"):format(n, n)
	end

	return source
end

return M
