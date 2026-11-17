--- The files one local branch changed since it left the default branch: opened from the branch list (a
--- chain), the prompt filters them by path. The branch item carries `base`, so the files, the diffs and the
--- grep that follows are those of a commit's.
local commit_files = require("beast.libs.finder.source.git_commit_files")
local format = require("beast.libs.finder.format")

---@class Beast.Finder.Source.GitBranchFiles: Beast.Finder.ASource
local M = {}

M.live = false
M.async = true
M.auto_select = false
M.keep_order = true
M.count = format.ratio
M.preview = commit_files.preview
M.open = commit_files.open

---@param filter Beast.Finder.Filter
---@param cb fun(item: Beast.Finder.Item|nil)
function M.get(filter, cb)
	commit_files.list(filter, filter.ctx.branch, cb)
end

--- "<branch> › Files Changed (N)"; `items` is nil while loading.
---@param filter? Beast.Finder.Filter
---@param items? Beast.Finder.Item[]
---@return string
function M.title(filter, items)
	local branch = filter and filter.ctx and filter.ctx.branch
	if not branch then
		return "Files Changed"
	end
	local out = branch.name .. " › Files Changed"
	if items and #items > 0 and not items[1].message then
		out = out .. (" (%d%s)"):format(#items, filter.ctx.truncated and ", partial" or "")
	end
	return out
end

return M
