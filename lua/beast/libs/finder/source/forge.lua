--- What differs between the code hosts the finder reads from (GitHub, GitLab). The shared sources, the
--- preview and the chains ask here instead of naming a host; an item without `provider` is GitHub's.

---@class Beast.Finder.Forge
local M = {}

local MODULE = { github = "beast.libs.finder.source.gh.api", gitlab = "beast.libs.finder.source.gl.api" }
local NAME = { github = "GitHub", gitlab = "GitLab" }

---@param item { provider?: string }
---@return string
local function provider(item)
	return item.provider or "github"
end

--- The API module that reads for this item.
---@param item { provider?: string }
---@return Beast.Finder.Gh.Api
function M.api(item)
	return require(MODULE[provider(item)])
end

--- "GitHub" / "GitLab", for the messages shown to the user.
---@param item { provider?: string }
---@return string
function M.name(item)
	return NAME[provider(item)]
end

--- How the item is numbered in the host's own words: "#30", "!412".
---@param item { ref?: string, number: integer }
---@return string
function M.ref(item)
	return item.ref or ("#" .. item.number)
end

--- What the host calls a change request ("PR" / "MR").
---@param item { provider?: string }
---@return string
function M.review(item)
	return provider(item) == "gitlab" and "MR" or "PR"
end

--- What the host calls the place a change request lives in ("Repo" / "Project").
---@param item { provider?: string }
---@return string
function M.project(item)
	return provider(item) == "gitlab" and "Project" or "Repo"
end

return M
