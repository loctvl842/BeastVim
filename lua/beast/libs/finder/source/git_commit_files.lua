--- The files one local commit changed: opened from the commits list (a chain), the prompt filters them by
--- path. Rows, preview and Enter are those of the pull request's changed files.
local commit_preview = require("beast.libs.finder.source.gh.commit_preview")
local format = require("beast.libs.finder.format")
local pr_files = require("beast.libs.finder.source.gh_pr_files")

---@class Beast.Finder.Source.GitCommitFiles: Beast.Finder.ASource
local M = {}

M.live = false
M.async = true
M.auto_select = false
M.keep_order = true
M.count = format.ratio
M.preview = pr_files.preview

---@param text string
---@param is_error? boolean
---@return Beast.Finder.Item
local function message(text, is_error)
	return { idx = 1, score = 1, text = text, message = true, is_error = is_error }
end

--- The files `owner` changed: a commit, or a branch item with `base` (see `git_branch_files`).
---@param filter Beast.Finder.Filter
---@param owner Beast.Finder.Item
---@param cb fun(item: Beast.Finder.Item|nil)
function M.list(filter, owner, cb)
	commit_preview.detail(owner, function(result)
		if result.error then
			cb(message("git could not list the files:", true))
			cb(message(result.error.message, true))
		elseif #result.detail.files == 0 then
			cb(message("No files changed"))
		else
			filter.ctx.truncated = result.detail.truncated
			for i, file in ipairs(result.detail.files) do
				cb({
					idx = i,
					score = 0,
					text = file.path,
					file = file.path,
					cwd = filter.cwd,
					commit = owner,
					status = file.status,
					previous = file.previous,
					additions = file.additions,
					deletions = file.deletions,
					patch = file.patch,
				})
			end
		end
		cb(nil)
	end)
end

---@param filter Beast.Finder.Filter
---@param cb fun(item: Beast.Finder.Item|nil)
function M.get(filter, cb)
	M.list(filter, filter.ctx.commit, cb)
end

--- "<id> <subject> › Files Changed (N)"; `items` is nil while loading.
---@param filter? Beast.Finder.Filter
---@param items? Beast.Finder.Item[]
---@return string
function M.title(filter, items)
	local commit = filter and filter.ctx and filter.ctx.commit
	if not commit then
		return "Files Changed"
	end
	local out = format.commit_trail(commit) .. " › Files Changed"
	if items and #items > 0 and not items[1].message then
		out = out .. (" (%d%s)"):format(#items, filter.ctx.truncated and ", partial" or "")
	end
	return out
end

function M.open(session, item)
	require("beast.libs.finder.action").open_diff(session.main_win, item)
end

return M
