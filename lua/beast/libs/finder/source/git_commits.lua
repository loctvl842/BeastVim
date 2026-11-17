--- The commits of the local repository, latest first: the prompt filters them by id, subject or author.
--- Each commit previews its diff; Enter shows the whole commit in a scratch buffer. A chain leads from here
--- to the files the commit changed.
local format = require("beast.libs.finder.format")
local log = require("beast.libs.finder.source.git.log")

---@class Beast.Finder.Source.GitCommits: Beast.Finder.ASource
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
	filter.ctx = filter.ctx or {}
	---@param result Beast.Finder.Git.CommitsResult
	local function emit(result)
		if result.error then
			cb(message("git could not list the commits:", true))
			cb(message(result.error.message, true))
		elseif #result.commits == 0 then
			cb(message("No commits"))
		else
			filter.ctx.truncated = result.truncated
			for i, commit in ipairs(result.commits) do
				cb({
					idx = i,
					score = 0,
					text = ("%s %s %s"):format(commit.short, commit.subject, commit.author),
					cwd = filter.cwd,
					sha = commit.sha,
					short = commit.short,
					subject = commit.subject,
					body = commit.message,
					author = commit.author,
					date = commit.date,
				})
			end
		end
		cb(nil)
	end
	local branch = filter.ctx.branch
	if not branch then
		log.commits(filter.cwd, emit)
		return
	end
	-- A branch lists what it added over the default branch; with nothing to compare, its whole history.
	local ref = "refs/heads/" .. branch.name
	log.base(filter.cwd, branch, branch.default, function(base)
		log.commits(filter.cwd, emit, base and (base .. ".." .. ref) or ref)
	end)
end

--- "Commits (N)", "<branch> › Commits (N)" for the commits of a branch; `items` is nil while loading.
---@param filter? Beast.Finder.Filter
---@param items? Beast.Finder.Item[]
---@return string
function M.title(filter, items)
	local branch = filter and filter.ctx and filter.ctx.branch
	local out = branch and (branch.name .. " › Commits") or "Commits"
	if items and #items > 0 and not items[1].message then
		out = out .. (" (%d%s)"):format(#items, filter and filter.ctx and filter.ctx.truncated and ", latest only" or "")
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
