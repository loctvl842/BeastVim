--- What the preview pane shows for a local branch: the commits it has over the default branch (or its
--- latest commits when there is nothing to compare). One `git merge-base` and one `git log` per branch,
--- kept for the session by the tip they were read at.
local diff = require("beast.libs.finder.ui.diff")
local log = require("beast.libs.finder.source.git.log")

---@class Beast.Finder.Git.BranchPreview
local M = {}

---@type table<string, Beast.View.DiffRow[]>
local cache = {}
local cached = 0
local MAX_CACHED = 30
local MARK = "git-branch:"

--- Forget the branches read so far (for tests).
function M.reset()
	cache, cached = {}, 0
end

---@param item Beast.Finder.Item a branch item
---@return string
local function key(item)
	return ("%s@%s@%s"):format(item.cwd, item.name, item.sha)
end

---@param item Beast.Finder.Item a branch item
---@param base? string
---@param result Beast.Finder.Git.CommitsResult
---@return Beast.View.DiffRow[]
local function rows(item, base, result)
	if result.error then
		return { diff.plain("Could not list the commits: " .. result.error.message) }
	end
	local n = #result.commits
	local head
	if base then
		head = ("%d commit%s ahead of %s"):format(n, n == 1 and "" or "s", item.default)
	else
		head = result.truncated and ("latest %d commits"):format(n) or "all commits"
	end
	local out = { diff.plain(head, "BeastViewDiffHead"), diff.plain("") }
	for _, commit in ipairs(result.commits) do
		out[#out + 1] = diff.plain(("%s  %s"):format(commit.short, commit.subject))
	end
	return out
end

--- Read the commits of `item`; the handle stops whichever git call is running.
---@param item Beast.Finder.Item a branch item
---@param cb fun(rows: Beast.View.DiffRow[])
---@return Beast.Finder.Gh.Handle
local function fetch(item, cb)
	local stopped = false
	local commits ---@type Beast.Finder.Gh.Handle?
	local base_proc = log.base(item.cwd, item, item.default, function(base)
		-- stylua: ignore
		if stopped then return end
		local ref = "refs/heads/" .. item.name
		commits = log.commits(item.cwd, function(result)
			-- stylua: ignore
			if stopped then return end
			local out = rows(item, base, result)
			if not result.error then
				if cached >= MAX_CACHED then
					cache, cached = {}, 0
				end
				cache[key(item)] = out
				cached = cached + 1
			end
			cb(out)
		end, base and (base .. ".." .. ref) or ref)
	end)
	return {
		kill = function()
			stopped = true
			for _, proc in ipairs({ base_proc or false, commits or false }) do
				if proc then
					proc.kill()
				end
			end
		end,
	}
end

---@class Beast.Finder.Git.BranchPreviewState
---@field key? string branch shown (late answers for another one are dropped)
---@field proc? Beast.Finder.Gh.Handle
---@type table<Beast.Finder.PreviewView, Beast.Finder.Git.BranchPreviewState>
local states = setmetatable({}, { __mode = "k" })

--- `source.preview` hook: draw the branch `item` in the preview pane.
---@param view Beast.Finder.PreviewView
---@param item? Beast.Finder.Item nil when the list is empty
function M.show(view, item)
	-- stylua: ignore
	if not view:is_valid() then return end
	local state = states[view] or {}
	states[view] = state
	if state.proc then
		state.proc.kill()
		state.proc = nil
	end
	if not item or item.message then
		state.key = nil
		return require("beast.libs.finder.ui.preview").clear(view)
	end
	local id = key(item)
	-- The pane may have been used by another level since (a push or pop clears it): it shows this branch only
	-- when it still carries the branch's marker.
	-- stylua: ignore
	if state.key == id and view.loaded_file == MARK .. id then return end
	state.key = id
	local function draw(out)
		-- stylua: ignore
		if state.key ~= id or not view:is_valid() then return end
		state.proc = nil
		diff.draw(view, out, " " .. item.name .. " ")
		view.loaded_file = MARK .. id
	end
	if cache[id] then
		return draw(cache[id])
	end
	state.proc = fetch(item, draw)
end

return M
