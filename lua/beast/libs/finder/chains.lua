--- The map of chains: what a picker can lead to next. One row per edge (`from` source to `to` source).
--- The edges are built in and closed: no other pair is supported (`chain.edge` raises for it).
---
--- `open(ctx)` builds the next level: a table of level options (see `Beast.Finder.LevelOpts`), a
--- string (a message shown to the user, nothing opens) or nil ("nothing to open from here").
--- `hint(ctx)` is the text shown after the key in the hint line under the picker; nil hides it.
local format = require("beast.libs.finder.format")

---@class Beast.Finder.ChainCtx
---@field items? Beast.Finder.Item[] every item that matches the prompt (only given to `open`; nil while the picker is still working)
---@field selected? Beast.Finder.Item|Beast.Finder.Gh.Item the highlighted item
---@field total integer how many items match the prompt
---@field filter Beast.Finder.Filter

---@class Beast.Finder.Edge
---@field id string "from|to", the name of the edge in the configuration
---@field from Beast.Finder.Source
---@field to Beast.Finder.Source
---@field key string key that follows the edge (default `<C-g>`; the configuration can change it)
---@field crumb string name of the `from` picker, shown as "<BS> back to <crumb>"
---@field hint fun(ctx: Beast.Finder.ChainCtx): string?
---@field open fun(ctx: Beast.Finder.ChainCtx): Beast.Finder.LevelOpts|string|nil|fun(resume: fun(result: Beast.Finder.LevelOpts|string|nil)): Beast.Finder.Gh.Handle? a function when the level needs a request first: it is called with `resume`, which takes what `open` would have returned

--- Paths of the items that are files, without repeats.
---@param items Beast.Finder.Item[]
---@return string[]
local function file_paths(items)
	local seen, paths = {}, {}
	for _, item in ipairs(items) do
		if item.file and not seen[item.file] then
			seen[item.file] = true
			paths[#paths + 1] = item.file
		end
	end
	return paths
end

---@param ctx Beast.Finder.ChainCtx
---@return string?
local function grep_files(ctx)
	return ctx.total > 0 and ("grep " .. ctx.total .. " files") or nil
end

--- The grep over the files behind the matching items, titled "<N> <what> › Live Grep".
---@param what string what the files are called ("Files", "Buffers", ...)
---@return fun(ctx: Beast.Finder.ChainCtx): Beast.Finder.LevelOpts?
local function scope_files(what)
	return function(ctx)
		local paths = file_paths(ctx.items)
		if #paths == 0 then
			return nil
		end
		return { files = paths, title = ("%d %s › Live Grep"):format(#paths, what) }
	end
end

---@param ctx Beast.Finder.ChainCtx
---@return string?
local function grep_help(ctx)
	return ctx.total > 0 and "grep the matching help pages" or nil
end

---@param ctx Beast.Finder.ChainCtx
---@return string?
local function files_in_pr(ctx)
	local pr = ctx.selected ---@cast pr Beast.Finder.Gh.Item?
	return pr and not pr.message and ("files changed in #" .. pr.number) or nil
end

---@param ctx Beast.Finder.ChainCtx
---@return Beast.Finder.LevelOpts?
local function pr_files(ctx)
	local pr = ctx.selected
	if not pr or pr.message then
		return nil
	end
	return {
		ctx = { pr = pr },
		title = require("beast.libs.finder.source.gh_pr_files").title({ ctx = { pr = pr } }),
	}
end

---@param ctx Beast.Finder.ChainCtx
---@return string?
local function commits_in_pr(ctx)
	local pr = ctx.selected ---@cast pr Beast.Finder.Gh.Item?
	return pr and not pr.message and ("commits in #" .. pr.number) or nil
end

---@param ctx Beast.Finder.ChainCtx
---@return Beast.Finder.LevelOpts?
local function pr_commits(ctx)
	local pr = ctx.selected
	if not pr or pr.message then
		return nil
	end
	return {
		ctx = { pr = pr },
		title = require("beast.libs.finder.source.gh_commits").title({ ctx = { pr = pr } }),
	}
end

---@param ctx Beast.Finder.ChainCtx
---@return string?
local function grep_local_copies(ctx)
	return ctx.total > 0 and "grep your local copies" or nil
end

--- The grep over the working-tree copies of the files a pull request changes: files it removes or that
--- are not in this checkout are left out.
---@param ctx Beast.Finder.ChainCtx
---@return Beast.Finder.LevelOpts|string|nil
local function scope_local_copies(ctx)
	local paths, listed = {}, 0
	for _, item in
		ipairs(ctx.items --[[@as Beast.Finder.Gh.FileItem[] ]])
	do
		-- A message row (an error, no files) is not a file.
		if not item.message then
			listed = listed + 1
			local abs = ctx.filter.cwd .. "/" .. item.file
			if item.status ~= "removed" and vim.uv.fs_stat(abs) then
				paths[#paths + 1] = abs
			end
		end
	end
	if listed == 0 then
		return nil
	end
	if #paths == 0 then
		return "None of these files exist in your working tree"
	end
	local commit = ctx.filter.ctx and ctx.filter.ctx.commit
	return {
		files = paths,
		ctx = { local_copies = true, commit = commit and commit.short },
		title = commit and ("%s › %s › %d Files › Live Grep"):format(format.pr_label(commit.pr), format.commit_label(commit), #paths)
			or ("%d PR Files › Live Grep"):format(#paths),
	}
end

---@param ctx Beast.Finder.ChainCtx
---@return string?
local function grep_issues(ctx)
	return ctx.selected and not ctx.selected.message and ("grep " .. ctx.total .. " issues") or nil
end

---@param ctx Beast.Finder.ChainCtx
---@return Beast.Finder.LevelOpts?
local function scope_issues(ctx)
	local issues = vim.tbl_filter(function(item)
		return not item.message
	end, ctx.items)
	if #issues == 0 then
		return nil
	end
	return { ctx = { issues = issues }, title = ("%d Issues › Live Grep"):format(#issues) }
end

---@param ctx Beast.Finder.ChainCtx
---@return string?
local function files_in_commit(ctx)
	local commit = ctx.selected
	return commit and not commit.message and "files changed" or nil
end

---@param ctx Beast.Finder.ChainCtx
---@return Beast.Finder.LevelOpts?
local function commit_files(ctx)
	local commit = ctx.selected
	if not commit or commit.message then
		return nil
	end
	return { ctx = { commit = commit }, title = require("beast.libs.finder.source.gh_commit_files").title({ ctx = { commit = commit } }) }
end

---@param ctx Beast.Finder.ChainCtx
---@return string?
local function grep_commit_files(ctx)
	local commit = ctx.selected
	return commit and not commit.message and "grep its files" or nil
end

--- The grep over the local copies of the files one commit changed. The commit's files are only known after
--- a request (instant when the preview already fetched them), so this answers later.
---@param ctx Beast.Finder.ChainCtx
---@return (fun(resume: fun(result: Beast.Finder.LevelOpts|string|nil)): Beast.Finder.Gh.Handle?)?
local function scope_commit_files(ctx)
	local commit = ctx.selected
	if not commit or commit.message then
		return nil
	end
	local cwd = ctx.filter.cwd
	return function(resume)
		return require("beast.libs.finder.source.gh.commit_preview").detail(commit, function(result)
			if result.error then
				return resume(result.error.message)
			end
			local files = result.detail.files
			if #files == 0 then
				return resume(nil)
			end
			local paths = {}
			for _, file in ipairs(files) do
				local abs = cwd .. "/" .. file.path
				if file.status ~= "removed" and vim.uv.fs_stat(abs) then
					paths[#paths + 1] = abs
				end
			end
			if #paths == 0 then
				return resume("None of these files exist in your working tree")
			end
			resume({
				files = paths,
				ctx = { local_copies = true, commit = commit.short },
				title = ("%s › %s › %d Files%s › Live Grep"):format(
					format.pr_label(commit.pr),
					format.commit_label(commit),
					#paths,
					result.detail.truncated and " (partial)" or ""
				),
			})
		end)
	end
end

local edges = {
	{ from = "files", to = "live_grep", crumb = "Files", hint = grep_files, open = scope_files("Files") },
	{ from = "buffers", to = "live_grep", crumb = "Buffers", hint = grep_files, open = scope_files("Buffers") },
	{ from = "gh_pr", to = "gh_pr_files", crumb = "Pull Requests", hint = files_in_pr, open = pr_files },
	{ from = "gh_pr", to = "gh_commits", key = "<C-t>", crumb = "Pull Requests", hint = commits_in_pr, open = pr_commits },
	{ from = "gh_commits", to = "gh_commit_files", crumb = "Commits", hint = files_in_commit, open = commit_files },
	{ from = "gh_commits", to = "live_grep", key = "<C-f>", crumb = "Commits", hint = grep_commit_files, open = scope_commit_files },
	{ from = "gh_commit_files", to = "live_grep", crumb = "Files Changed", hint = grep_local_copies, open = scope_local_copies },
	{ from = "gh_pr_files", to = "live_grep", crumb = "Files Changed", hint = grep_local_copies, open = scope_local_copies },
	{ from = "gh_issue", to = "gh_issue_grep", crumb = "Issues", hint = grep_issues, open = scope_issues },
	{ from = "help_tags", to = "live_grep", crumb = "Help", hint = grep_help, open = scope_files("Help Files") },
}

for _, edge in ipairs(edges) do
	edge.id = edge.from .. "|" .. edge.to
	edge.key = edge.key or "<C-g>"
end

return edges --[[@as Beast.Finder.Edge[] ]]
