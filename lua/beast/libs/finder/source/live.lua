--- Factory for the live pickers of a code host (`gh_pr`, `gh_issue`, `gl_mr`, `gl_issue`): the prompt text is
--- the host's query, every pause in typing runs one search and feeds its answer to the live (stream) pipeline.
--- A host supplies what differs (`Beast.Finder.LiveSpec`); stale answers, message rows and the count live here.

---@class Beast.Finder.LiveSpec
---@field name string "GitHub": how the host is named in messages
---@field title string "Pull Requests": start of the title bar
---@field initial_query string prompt text the picker opens with
---@field debounce_ms integer wait for typing to pause
---@field check fun(cwd: string): Beast.Git.Remote?, string? the project, or nil plus the reason to show
---@field scope fun(text: string, repo: Beast.Git.Remote): string what the title bar names after the title
---@field search fun(text: string, repo: Beast.Git.Remote, done: fun(result: Beast.Finder.Gh.Result)): Beast.Finder.Gh.Handle one search; `done` is not called for a killed one

---@class Beast.Finder.Source.Live
local M = {}

--- A row that explains the list instead of being an item.
---@param text string
---@param is_error? boolean
---@return Beast.Finder.Item
local function message(text, is_error)
	return { idx = 1, score = 1, text = text, message = true, is_error = is_error }
end

---@param spec Beast.Finder.LiveSpec
---@return Beast.Finder.ASource
function M.create(spec)
	local repo ---@type Beast.Git.Remote? set by check(), which always runs before a picker opens
	local generation = 0 -- bumped on every search and cancel; late responses of older ones are dropped
	local handle ---@type Beast.Finder.Gh.Handle?
	local total = 0 -- matches the host reported for the last finished search
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
		debounce_ms = spec.debounce_ms,
		initial_query = spec.initial_query,
		cancel = stop,
		format = require("beast.libs.finder.format").gh,
	}

	source.preview = function(view, item)
		require("beast.libs.finder.source.gh.preview").show(view, item)
	end

	function source.check()
		local found, err = spec.check(Util.root())
		if not found then
			Toast(err, vim.log.levels.WARN)
			return false
		end
		repo = found
		return true
	end

	function source.title(filter)
		local scope = repo and spec.scope(filter and filter.pattern or source.initial_query, repo) or ""
		return ("%s - %s"):format(spec.title, scope)
	end

	function source.get(filter, cb)
		stop()
		local mine = generation
		---@cast repo Beast.Git.Remote
		handle = spec.search(filter.pattern, repo, function(result)
			-- stylua: ignore
			if mine ~= generation then return end
			handle = nil
			total = 0
			failed = result.error ~= nil
			if result.error then
				local err = result.error
				if not err.bare then
					cb(message(spec.name .. " could not run this search:", true))
				end
				cb(message(err.message, true))
				-- message rows do not wrap: a long hint arrives as one line per row
				for line in vim.gsplit(err.hint or "", "\n", { plain = true, trimempty = true }) do
					cb(message(line, true))
				end
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
