--- The local branches of the repository, the one you are on first: the prompt filters them by name, latest
--- commit or author. Each branch previews the commits it has over the default branch; Enter shows its latest
--- commit (nothing is checked out). Chains lead from here to the files the branch changed and to its commits.
local format = require("beast.libs.finder.format")
local log = require("beast.libs.finder.source.git.log")

---@class Beast.Finder.Source.GitBranches: Beast.Finder.ASource
local M = {}

M.live = false
M.async = true
M.auto_select = false
M.keep_order = true
M.count = format.ratio
M.format = format.git_branch

---@param text string
---@param is_error? boolean
---@return Beast.Finder.Item
local function message(text, is_error)
	return { idx = 1, score = 1, text = text, message = true, is_error = is_error }
end

---@param filter Beast.Finder.Filter
---@param cb fun(item: Beast.Finder.Item|nil)
function M.get(filter, cb)
	log.branches(filter.cwd, function(result)
		if result.error then
			if result.error.message:lower():find("not a git repository", 1, true) then
				cb(message("Not a git repository"))
			else
				cb(message("git could not list the branches:", true))
				cb(message(result.error.message, true))
			end
		elseif #result.branches == 0 then
			cb(message("No branches"))
		else
			local default = log.default_name(result.branches)
			for i, branch in ipairs(result.branches) do
				cb({
					idx = i,
					score = 0,
					text = ("%s %s %s"):format(branch.name, branch.subject, branch.author),
					cwd = filter.cwd,
					name = branch.name,
					current = branch.current,
					default = default,
					sha = branch.sha,
					short = branch.short,
					subject = branch.subject,
					body = branch.message,
					author = branch.author,
					date = branch.date,
				})
			end
		end
		cb(nil)
	end)
end

--- "Git Branches (N)"; `items` is nil while loading.
---@param filter? Beast.Finder.Filter
---@param items? Beast.Finder.Item[]
---@return string
function M.title(filter, items)
	if items and #items > 0 and not items[1].message then
		return ("Git Branches (%d)"):format(#items)
	end
	return "Git Branches"
end

M.preview = function(view, item)
	require("beast.libs.finder.source.git.branch_preview").show(view, item)
end

function M.open(session, item)
	require("beast.libs.finder.action").open_commit(session.main_win, item)
end

return M
