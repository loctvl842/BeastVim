--- The commits of the local repository, read with `git`: the list (`git log`) and one commit with the files
--- it changed (`git show`). Commits and files come out in the shapes the GitHub commit sources use, so the
--- preview, the titles and the grep step are shared.
---@class Beast.Finder.Git.Log
local M = {}

--- How many commits the list keeps (the latest ones).
M.LIMIT = 500
--- A commit shows at most this many files (what GitHub shows too); `truncated` says when there were more.
M.MAX_FILES = 300

local FIELD, RECORD = "\31", "\30"
local STATUS = { A = "added", M = "modified", D = "removed", R = "renamed", C = "copied", T = "changed" }

---@param res vim.SystemCompleted
---@return Beast.Finder.Gh.Error
local function failure(res)
	local text = vim.trim(res.stderr or "")
	return { kind = "other", message = text ~= "" and text or ("git failed (exit %d)"):format(res.code) }
end

--- Run `git` in `cwd`; `cb` runs on the main loop, also after `kill()`.
---@param cwd string
---@param args string[]
---@param cb fun(res: vim.SystemCompleted)
---@return Beast.Finder.Gh.Handle
local function git(cwd, args, cb)
	local proc = vim.system(vim.list_extend({ "git", "-C", cwd }, args), { text = true }, function(res)
		vim.schedule(function()
			cb(res)
		end)
	end)
	return {
		kill = function()
			pcall(proc.kill, proc, 15)
		end,
	}
end

---@param stdout string
---@return Beast.Finder.Gh.Commit[]
function M.parse_log(stdout)
	local commits = {}
	for record in stdout:gmatch("([^" .. RECORD .. "]+)") do
		local sha, author, date, message =
			record:match("^%s*(%x+)" .. FIELD .. "([^" .. FIELD .. "]*)" .. FIELD .. "([^" .. FIELD .. "]*)" .. FIELD .. "(.*)$")
		if sha then
			message = vim.trim(message)
			commits[#commits + 1] = {
				sha = sha,
				short = sha:sub(1, 7),
				subject = message:match("^[^\n]*"),
				message = message,
				author = author,
				date = date,
			}
		end
	end
	return commits
end

---@class Beast.Finder.Git.CommitsResult
---@field commits? Beast.Finder.Gh.Commit[] latest first
---@field truncated? boolean the history is longer than `LIMIT`
---@field error? Beast.Finder.Gh.Error

--- The latest `LIMIT` commits of the repository at `cwd`, newest first. `rev` is what `git log` walks
--- (a ref or a range such as "base..refs/heads/x"); nil means `HEAD`.
---@param cwd string
---@param cb fun(result: Beast.Finder.Git.CommitsResult)
---@param rev? string
---@return Beast.Finder.Gh.Handle
function M.commits(cwd, cb, rev)
	local format = table.concat({ "%H", "%an", "%aI", "%B" }, FIELD) .. RECORD
	local args = { "log", "-n", tostring(M.LIMIT + 1), "--format=" .. format }
	if rev then
		args[#args + 1] = rev
	end
	return git(cwd, args, function(res)
		if res.code ~= 0 then
			return cb({ error = failure(res) })
		end
		local commits = M.parse_log(res.stdout or "")
		local truncated = #commits > M.LIMIT
		commits[M.LIMIT + 1] = nil
		cb({ commits = commits, truncated = truncated })
	end)
end

--- The files of `git show --raw --numstat --patch` output: the three parts list the same files in the same
--- order, so they are put together by position.
---@param stdout string
---@return Beast.Finder.Gh.File[]
function M.parse_show(stdout)
	local files, counts, patches = {}, {}, {}
	local patch ---@type string[]?
	for line in (stdout .. "\n"):gmatch("(.-)\n") do
		if patch then
			if line:sub(1, 11) == "diff --git " then
				patches[#patches + 1] = patch
				patch = {}
			else
				patch[#patch + 1] = line
			end
		elseif line:sub(1, 11) == "diff --git " then
			patch = {}
		elseif line:sub(1, 1) == ":" then
			local code, path, renamed = line:match("^:%S+ %S+ %S+ %S+ (%a)%d*\t([^\t]+)\t?([^\t]*)$")
			if code then
				local previous = renamed ~= "" and path or nil
				files[#files + 1] = { path = previous and renamed or path, previous = previous, status = STATUS[code] or "changed" }
			end
		else
			local added, deleted = line:match("^(%S+)\t(%S+)\t")
			if added then
				counts[#counts + 1] = { tonumber(added) or 0, tonumber(deleted) or 0 }
			end
		end
	end
	if patch then
		patches[#patches + 1] = patch
	end
	for i, file in ipairs(files) do
		file.additions, file.deletions = counts[i][1], counts[i][2]
		-- Everything before the first hunk is the file header; a binary file has no hunk.
		local body = patches[i] or {}
		for n, text in ipairs(body) do
			if text:sub(1, 2) == "@@" then
				file.patch = table.concat(body, "\n", n)
				break
			end
		end
	end
	return files
end

--- The files of `git show` / `git diff` output as a commit detail, cut at `MAX_FILES`.
---@param res vim.SystemCompleted
---@return Beast.Finder.Gh.CommitDetailResult
local function detail_result(res)
	if res.code ~= 0 then
		return { error = failure(res) }
	end
	local files = M.parse_show(res.stdout or "")
	local truncated = #files > M.MAX_FILES
	for i = #files, M.MAX_FILES + 1, -1 do
		files[i] = nil
	end
	return { detail = { message = "", files = files, truncated = truncated } }
end

--- One commit with the files it changed (a merge shows what it brought in from the other parents).
---@param cwd string
---@param sha string
---@param cb fun(result: Beast.Finder.Gh.CommitDetailResult)
---@return Beast.Finder.Gh.Handle
function M.show(cwd, sha, cb)
	local args = { "show", "--format=", "-M", "--raw", "--numstat", "--patch", "--relative", "--diff-merges=first-parent", sha }
	return git(cwd, args, function(res)
		cb(detail_result(res))
	end)
end

--- What changed from `base` to `tip`, in the shape of a commit's detail.
---@param cwd string
---@param base string
---@param tip string
---@param cb fun(result: Beast.Finder.Gh.CommitDetailResult)
---@return Beast.Finder.Gh.Handle
function M.diff(cwd, base, tip, cb)
	local args = { "diff", "-M", "--raw", "--numstat", "--patch", "--relative", base, tip }
	return git(cwd, args, function(res)
		cb(detail_result(res))
	end)
end

---@class Beast.Finder.Git.Branch: Beast.Finder.Gh.Commit
---@field name string
---@field current boolean

---@class Beast.Finder.Git.BranchesResult
---@field branches? Beast.Finder.Git.Branch[] the branch you are on first, then the newest first
---@field error? Beast.Finder.Gh.Error

--- The local branches of the repository at `cwd`, each with its latest commit.
---@param cwd string
---@param cb fun(result: Beast.Finder.Git.BranchesResult)
---@return Beast.Finder.Gh.Handle
function M.branches(cwd, cb)
	local format = table.concat({ "%(HEAD)", "%(refname:short)", "%(objectname)", "%(authorname)", "%(authordate:iso-strict)", "%(contents)" }, FIELD)
		.. RECORD
	local args = { "for-each-ref", "--sort=-committerdate", "--format=" .. format, "refs/heads" }
	return git(cwd, args, function(res)
		if res.code ~= 0 then
			return cb({ error = failure(res) })
		end
		local branches = {}
		for record in (res.stdout or ""):gmatch("([^" .. RECORD .. "]+)") do
			local head, name, sha, author, date, message = record:gsub("^\n", ""):match(
				"^([%* ])"
					.. FIELD
					.. "([^"
					.. FIELD
					.. "]*)"
					.. FIELD
					.. "(%x+)"
					.. FIELD
					.. "([^"
					.. FIELD
					.. "]*)"
					.. FIELD
					.. "([^"
					.. FIELD
					.. "]*)"
					.. FIELD
					.. "(.*)$"
			)
			if name then
				message = vim.trim(message)
				local branch = {
					name = name,
					current = head == "*",
					sha = sha,
					short = sha:sub(1, 7),
					subject = message:match("^[^\n]*"),
					message = message,
					author = author,
					date = date,
				}
				table.insert(branches, branch.current and 1 or #branches + 1, branch)
			end
		end
		cb({ branches = branches })
	end)
end

--- The branch changes are compared against: `main`, else `master`, else nil.
---@param branches Beast.Finder.Git.Branch[]
---@return string?
function M.default_name(branches)
	local names = {}
	for _, branch in ipairs(branches) do
		names[branch.name] = true
	end
	return (names.main and "main") or (names.master and "master") or nil
end

--- Where `branch` left `default`: the commit its own changes start from. Nil (and `cb` runs at once) when
--- there is nothing to compare: no default branch, the branch is the default, it has no commit of its own,
--- or the two share no history.
---@param cwd string
---@param branch Beast.Finder.Git.Branch
---@param default? string
---@param cb fun(base: string?)
---@return Beast.Finder.Gh.Handle?
function M.base(cwd, branch, default, cb)
	if not default or default == branch.name then
		return cb(nil)
	end
	return git(cwd, { "merge-base", "refs/heads/" .. default, "refs/heads/" .. branch.name }, function(res)
		local base = res.code == 0 and vim.trim(res.stdout or "") or nil
		cb(base ~= branch.sha and base or nil)
	end)
end

return M
