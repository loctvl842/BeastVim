--- The commits of a pull request: opened from the pull request list (a chain), the prompt filters them by
--- id, subject or author. Each commit previews its diff; Enter shows the whole commit in a scratch buffer.
local api = require("beast.libs.finder.source.gh.api")
local format = require("beast.libs.finder.format")

---@class Beast.Finder.Source.GhCommits: Beast.Finder.ASource
local M = {}

M.live = false
M.async = true
M.auto_select = false
M.keep_order = true
M.count = format.ratio
M.format = format.gh_commit

---@param text string
---@param is_error? boolean
---@return Beast.Finder.Item
local function message(text, is_error)
	return { idx = 1, score = 1, text = text, message = true, is_error = is_error }
end

---@param filter Beast.Finder.Filter
---@param cb fun(item: Beast.Finder.Item|nil)
function M.get(filter, cb)
	---@type Beast.Finder.Gh.Item
	local pr = filter.ctx.pr
	api.commits(pr, function(result)
		if result.error then
			cb(message("GitHub could not list the commits:", true))
			cb(message(result.error.message, true))
		elseif #result.commits == 0 then
			cb(message("No commits"))
		else
			filter.ctx.truncated = result.truncated
			-- GitHub lists the oldest first; the latest commit is the one you want first.
			for i = #result.commits, 1, -1 do
				local commit = result.commits[i]
				cb({
					idx = #result.commits - i + 1,
					score = 0,
					text = ("%s %s %s"):format(commit.short, commit.subject, commit.author),
					cwd = filter.cwd,
					pr = pr,
					sha = commit.sha,
					short = commit.short,
					subject = commit.subject,
					body = commit.message,
					author = commit.author,
					date = commit.date,
					url = ("https://%s/%s/commit/%s"):format(pr.host, pr.repo, commit.sha),
				})
			end
		end
		cb(nil)
	end)
end

--- "PR <title> › Commits (N)"; `items` is nil while loading.
---@param filter? Beast.Finder.Filter
---@param items? Beast.Finder.Item[]
---@return string
function M.title(filter, items)
	local pr = filter and filter.ctx and filter.ctx.pr
	if not pr then
		return "Commits"
	end
	local out = format.pr_label(pr) .. " › Commits"
	if items and #items > 0 and not items[1].message then
		out = out .. (" (%d%s)"):format(#items, filter.ctx.truncated and ", partial" or "")
	end
	return out
end

M.preview = function(view, item)
	require("beast.libs.finder.source.gh.commit_preview").show(view, item)
end

function M.open(session, item)
	require("beast.libs.finder.action").open_commit(session.main_win, item)
end

return M
