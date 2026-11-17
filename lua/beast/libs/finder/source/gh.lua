--- The GitHub sources (`gh_pr`, `gh_issue`): the prompt text is a GitHub search query, run through
--- `gh api`. The picker itself is the shared live source (`live.lua`).
local api = require("beast.libs.finder.source.gh.api")
local query = require("beast.libs.finder.source.gh.query")

---@class Beast.Finder.Source.Gh
local M = {}

local TITLES = { pr = "Pull Requests", issue = "Issues" }

---@param kind Beast.Finder.Gh.Kind
---@return Beast.Finder.ASource
function M.create(kind)
	return require("beast.libs.finder.source.live").create({
		name = "GitHub",
		title = TITLES[kind],
		initial_query = query.default_text(kind),
		-- GitHub search allows 30 requests a minute: wait for typing to pause.
		debounce_ms = 400,
		check = api.check,
		scope = function(text, repo)
			return query.scope(text, repo.slug)
		end,
		search = function(text, repo, done)
			return api.search(query.build(text, repo.slug), repo.host, done)
		end,
	})
end

return M
