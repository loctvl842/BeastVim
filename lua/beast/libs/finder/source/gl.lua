--- The GitLab sources (`gl_mr`, `gl_issue`): the prompt text holds filter flags and free words, turned into
--- the parameters of one `glab api` list request. The picker itself is the shared live source (`live.lua`).
local api = require("beast.libs.finder.source.gl.api")
local query = require("beast.libs.finder.source.gl.query")

---@class Beast.Finder.Source.Gl
local M = {}

local TITLES = { mr = "Merge Requests", issue = "Issues" }

---@param kind Beast.Finder.Gl.Kind
---@return Beast.Finder.ASource
function M.create(kind)
	--- One search. A text with a mistake answers at once, an empty answer for a named user first checks
	--- the user exists (GitLab answers an unknown username with an empty list).
	---@param text string
	---@param repo Beast.Git.Remote
	---@param done fun(result: Beast.Finder.Gh.Result)
	---@return Beast.Finder.Gh.Handle
	local function search(text, repo, done)
		local parsed = query.parse(text, kind)
		if parsed.error then
			done({ error = { kind = "other", message = parsed.error, hint = parsed.hint, bare = true } })
			return { kill = function() end }
		end

		local current ---@type Beast.Finder.Gh.Handle
		local killed = false

		local function check_users(i)
			local user = parsed.users[i]
			if not user then
				return done({ items = {} })
			end
			current = api.user_exists(repo.host, user.name, function(exists)
				-- stylua: ignore
				if killed then return end
				if exists then
					return check_users(i + 1)
				end
				done({ error = { kind = "other", message = ('user "%s" was not found'):format(user.name) } })
			end)
		end

		current = api.search(kind, parsed.project or repo.slug, parsed.params, repo.host, function(result)
			-- stylua: ignore
			if killed then return end
			if result.items and #result.items == 0 and #parsed.users > 0 then
				return check_users(1)
			end
			done(result)
		end)

		return {
			kill = function()
				killed = true
				current.kill()
			end,
		}
	end

	return require("beast.libs.finder.source.live").create({
		name = "GitLab",
		title = TITLES[kind],
		initial_query = query.default_text(kind),
		debounce_ms = 400,
		check = api.check,
		scope = function(text, repo)
			local scope = query.scope(text, repo.slug)
			return repo.host == "gitlab.com" and scope or (repo.host .. "/" .. scope)
		end,
		search = search,
	})
end

return M
