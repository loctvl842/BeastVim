--- Everything that talks to the `gh` CLI for the GitHub finder sources.
--- Search results are normalized into finder items here so no other module sees raw API JSON.

---@alias Beast.Finder.Gh.Repo Beast.Git.Remote

---@class Beast.Finder.Gh.Label
---@field name string
---@field color string hex without "#"

---@alias Beast.Finder.Gh.State "open"|"draft"|"merged"|"closed"|"not_planned"

---@class Beast.Finder.Gh.Item: Beast.Finder.Item
---@field kind Beast.Finder.Gh.Kind
---@field provider? "github"|"gitlab" absent means GitHub
---@field ref? string the number as the host writes it: "#30", "!412"
---@field state Beast.Finder.Gh.State
---@field number integer
---@field title string
---@field author? string
---@field labels Beast.Finder.Gh.Label[]
---@field url string
---@field repo string "owner/name"
---@field host string
---@field created string ISO timestamp
---@field updated string ISO timestamp
---@field comments integer
---@field body? string description (search results carry it; used by the issue grep)

---@class Beast.Finder.Gh.Error
---@field kind "not_found"|"rate_limit"|"auth"|"network"|"other"
---@field message string
---@field hint? string a second line of explanation
---@field bare? boolean the message stands alone, without "<host> could not run this search:" before it

---@class Beast.Finder.Gh.Result
---@field items? Beast.Finder.Gh.Item[]
---@field total? integer total matches on GitHub (may exceed #items)
---@field error? Beast.Finder.Gh.Error

---@class Beast.Finder.Gh.Handle
---@field kill fun()

local pager = require("beast.libs.finder.source.pager")

---@class Beast.Finder.Gh.Api
local M = {}

M.PER_PAGE = pager.PER_PAGE

-- ---------------------------------------------------------------------------
-- Repo detection and pre-flight (local only, no network)
-- ---------------------------------------------------------------------------

---@param cwd string
---@return Beast.Finder.Gh.Repo?
function M.repo(cwd)
	return Git.remote("github", cwd)
end

--- Can a search run here? Returns the repo, or nil plus the reason to show the user.
---@param cwd string
---@return Beast.Finder.Gh.Repo?
---@return string? err
function M.check(cwd)
	if vim.fn.executable("gh") ~= 1 then
		return nil, "GitHub CLI (gh) is not installed"
	end
	local repo = M.repo(cwd)
	if not repo then
		return nil, "No GitHub remote found for this directory"
	end
	local res = vim.system({ "gh", "auth", "token", "--hostname", repo.host }, { text = true }):wait()
	if res.code ~= 0 then
		-- A host gh knows nothing about is most likely not GitHub at all.
		if repo.host ~= "github.com" then
			return nil, "No GitHub remote found for this directory"
		end
		return nil, "Run `gh auth login` first"
	end
	return repo
end

-- ---------------------------------------------------------------------------
-- Search
-- ---------------------------------------------------------------------------

---@param raw table one element of search/issues `items`
---@param host string
---@return Beast.Finder.Gh.Item
function M.normalize(raw, host)
	local is_pr = raw.pull_request ~= nil
	local state ---@type Beast.Finder.Gh.State
	if is_pr then
		if raw.pull_request.merged_at then
			state = "merged"
		elseif raw.state == "closed" then
			state = "closed"
		else
			state = raw.draft and "draft" or "open"
		end
	elseif raw.state == "closed" then
		state = raw.state_reason == "not_planned" and "not_planned" or "closed"
	else
		state = "open"
	end

	local labels = {}
	for _, l in ipairs(raw.labels or {}) do
		labels[#labels + 1] = { name = l.name, color = l.color or "888888" }
	end

	return {
		text = ("#%d %s"):format(raw.number, raw.title or ""),
		kind = is_pr and "pr" or "issue",
		provider = "github",
		ref = "#" .. raw.number,
		state = state,
		number = raw.number,
		title = raw.title or "",
		author = raw.user and raw.user.login or nil,
		labels = labels,
		url = raw.html_url,
		repo = (raw.repository_url or ""):match("/repos/(.+)$") or "",
		host = host,
		created = raw.created_at,
		updated = raw.updated_at,
		comments = raw.comments or 0,
		body = raw.body,
	}
end

---@param res vim.SystemCompleted
---@return Beast.Finder.Gh.Error
local function classify(res)
	local err = res.stderr or ""
	local ok, body = pcall(vim.json.decode, res.stdout or "", { luanil = { object = true, array = true } })
	local api_msg = ok and type(body) == "table" and body.errors and body.errors[1] and body.errors[1].message or nil
	local lower = (err .. " " .. (ok and type(body) == "table" and body.message or "")):lower()

	if err:find("HTTP 422", 1, true) then
		if api_msg and api_msg:find("cannot be searched", 1, true) then
			return { kind = "not_found", message = "repository not found or no access to it" }
		end
		return { kind = "other", message = api_msg or "GitHub rejected this search" }
	end
	if lower:find("rate limit", 1, true) or err:find("HTTP 429", 1, true) then
		return { kind = "rate_limit", message = "GitHub search rate limit reached" }
	end
	if err:find("HTTP 401", 1, true) or err:find("gh auth login", 1, true) then
		return { kind = "auth", message = "GitHub login expired, run `gh auth login`" }
	end
	if lower:find("error connecting", 1, true) or lower:find("could not resolve", 1, true) then
		return { kind = "network", message = "cannot reach GitHub" }
	end
	local first = err:match("[^\r\n]+")
	return { kind = "other", message = first or ("gh exited with code " .. tostring(res.code)) }
end

---@param res vim.SystemCompleted
---@param host string
---@return Beast.Finder.Gh.Result
function M.parse(res, host)
	if res.code ~= 0 then
		return { error = classify(res) }
	end
	local ok, body = pcall(vim.json.decode, res.stdout or "", { luanil = { object = true, array = true } })
	if not ok or type(body) ~= "table" or type(body.items) ~= "table" then
		return { error = { kind = "other", message = "unexpected response from GitHub" } }
	end
	local items = {}
	for i, raw in ipairs(body.items) do
		items[i] = M.normalize(raw, host)
	end
	return { items = items, total = body.total_count or #items }
end

--- Tell the user when a rate-limited search window resets.
---@param host string
---@param err Beast.Finder.Gh.Error
---@param done fun()
local function add_reset_hint(host, err, done)
	vim.system(
		{ "gh", "api", "rate_limit", "--hostname", host, "--jq", ".resources.search.reset" },
		{ text = true },
		vim.schedule_wrap(function(res)
			local reset = res.code == 0 and tonumber(vim.trim(res.stdout or "")) or nil
			if reset then
				local secs = math.max(1, reset - os.time())
				err.message = ("%s, resets in %ds"):format(err.message, secs)
			end
			done()
		end)
	)
end

--- Run one search. `cb` is called on the main loop, also after `kill()` (with an error result);
--- callers that cancel must ignore it.
---@param q string full query (already built)
---@param host string
---@param cb fun(result: Beast.Finder.Gh.Result)
---@return Beast.Finder.Gh.Handle
function M.search(q, host, cb)
	local proc = vim.system({
		"gh",
		"api",
		"-X",
		"GET",
		"search/issues",
		"--hostname",
		host,
		"-f",
		"q=" .. q,
		"-f",
		"per_page=" .. M.PER_PAGE,
	}, { text = true }, function(res)
		vim.schedule(function()
			local result = M.parse(res, host)
			if result.error and result.error.kind == "rate_limit" then
				add_reset_hint(host, result.error, function()
					cb(result)
				end)
				return
			end
			cb(result)
		end)
	end)
	return {
		kill = function()
			pcall(proc.kill, proc, 15)
		end,
	}
end

--- Web address of a commit of `item`'s repository.
---@param item Beast.Finder.Gh.Item
---@param sha string
---@return string
function M.commit_url(item, sha)
	return ("https://%s/%s/commit/%s"):format(item.host, item.repo, sha)
end

-- ---------------------------------------------------------------------------
-- Files changed by a pull request
-- ---------------------------------------------------------------------------

---@class Beast.Finder.Gh.File
---@field path string
---@field previous? string path before a rename
---@field status string added|removed|modified|renamed|copied|changed|unchanged
---@field additions integer
---@field deletions integer
---@field patch? string unified diff; absent for binary or very large diffs

---@class Beast.Finder.Gh.FilesResult
---@field files? Beast.Finder.Gh.File[]
---@field truncated? boolean the pull request changes more files than `pager.PAGES` pages hold
---@field error? Beast.Finder.Gh.Error

---@param raw table one element of `pulls/{n}/files`
---@return Beast.Finder.Gh.File
function M.normalize_file(raw)
	return {
		path = raw.filename,
		previous = raw.previous_filename,
		status = raw.status or "modified",
		additions = raw.additions or 0,
		deletions = raw.deletions or 0,
		patch = raw.patch,
	}
end

--- Read a list endpoint of a pull request page by page (see `pager`). `cb` runs on the main loop, also
--- after `kill()`; callers that cancel must ignore it.
---@generic T
---@param item Beast.Finder.Gh.Item the pull request
---@param endpoint string "files" or "commits"
---@param normalize fun(raw: table): T
---@param cb fun(result: Beast.Finder.Pager.Result)
---@return Beast.Finder.Gh.Handle
local function pages(item, endpoint, normalize, cb)
	return pager.collect(function(page, done)
		return vim.system({
			"gh",
			"api",
			"-X",
			"GET",
			("repos/%s/pulls/%d/%s"):format(item.repo, item.number, endpoint),
			"--hostname",
			item.host,
			"-f",
			"per_page=" .. pager.PER_PAGE,
			"-f",
			"page=" .. page,
		}, { text = true }, function(res)
			vim.schedule(function()
				if res.code ~= 0 then
					return done({ error = classify(res) })
				end
				local ok, list = pcall(vim.json.decode, res.stdout or "", { luanil = { object = true, array = true } })
				if not ok or type(list) ~= "table" then
					return done({ error = { kind = "other", message = "unexpected response from GitHub" } })
				end
				done({ list = list })
			end)
		end)
	end, normalize, cb)
end

--- The files a pull request changes. `cb` runs on the main loop, also after `kill()`; callers that cancel must ignore it.
---@param item Beast.Finder.Gh.Item the pull request
---@param cb fun(result: Beast.Finder.Gh.FilesResult)
---@return Beast.Finder.Gh.Handle
function M.files(item, cb)
	return pages(item, "files", M.normalize_file, function(result)
		cb({ files = result.items, truncated = result.truncated, error = result.error })
	end)
end

---@class Beast.Finder.Gh.Commit
---@field sha string
---@field short string first 7 characters of `sha`
---@field subject string first line of the message
---@field message string
---@field author string login, else the name in the commit
---@field date string ISO timestamp

---@param raw table one element of `pulls/{n}/commits`
---@return Beast.Finder.Gh.Commit
function M.normalize_commit(raw)
	local message = raw.commit and raw.commit.message or ""
	local author = raw.commit and raw.commit.author or {}
	return {
		sha = raw.sha,
		short = raw.sha:sub(1, 7),
		subject = message:match("^[^\r\n]*"),
		message = message,
		author = raw.author and raw.author.login or author.name or "",
		date = author.date or "",
	}
end

---@class Beast.Finder.Gh.CommitsResult
---@field commits? Beast.Finder.Gh.Commit[]
---@field truncated? boolean the pull request has more commits than `pager.PAGES` pages hold
---@field error? Beast.Finder.Gh.Error

--- The commits of a pull request, oldest first (the order GitHub shows).
---@param item Beast.Finder.Gh.Item the pull request
---@param cb fun(result: Beast.Finder.Gh.CommitsResult)
---@return Beast.Finder.Gh.Handle
function M.commits(item, cb)
	return pages(item, "commits", M.normalize_commit, function(result)
		cb({ commits = result.items, truncated = result.truncated, error = result.error })
	end)
end

---@class Beast.Finder.Gh.CommitDetail
---@field message string
---@field files Beast.Finder.Gh.File[]
---@field truncated boolean GitHub lists at most 300 files of a commit

---@class Beast.Finder.Gh.CommitDetailResult
---@field detail? Beast.Finder.Gh.CommitDetail
---@field error? Beast.Finder.Gh.Error

--- One commit with the files it changed. `cb` runs on the main loop, also after `kill()`.
---@param item Beast.Finder.Gh.Item the pull request (for the repository)
---@param sha string
---@param cb fun(result: Beast.Finder.Gh.CommitDetailResult)
---@return Beast.Finder.Gh.Handle
function M.commit(item, sha, cb)
	local proc = vim.system({
		"gh",
		"api",
		"-X",
		"GET",
		("repos/%s/commits/%s"):format(item.repo, sha),
		"--hostname",
		item.host,
	}, { text = true }, function(res)
		vim.schedule(function()
			if res.code ~= 0 then
				return cb({ error = classify(res) })
			end
			local ok, raw = pcall(vim.json.decode, res.stdout or "", { luanil = { object = true, array = true } })
			if not ok or type(raw) ~= "table" then
				return cb({ error = { kind = "other", message = "unexpected response from GitHub" } })
			end
			local files = {}
			for _, file in ipairs(raw.files or {}) do
				files[#files + 1] = M.normalize_file(file)
			end
			cb({ detail = { message = raw.commit and raw.commit.message or "", files = files, truncated = #files >= 300 } })
		end)
	end)
	return {
		kill = function()
			pcall(proc.kill, proc, 15)
		end,
	}
end

-- ---------------------------------------------------------------------------
-- Detail (preview pane)
-- ---------------------------------------------------------------------------

---@class Beast.Finder.Gh.Checks
---@field passed integer
---@field failed integer
---@field pending integer

---@class Beast.Finder.Gh.ConversationEntry
---@field author? string
---@field body string
---@field created string
---@field state? string review verdict (APPROVED, CHANGES_REQUESTED, ...), nil for plain comments

---@class Beast.Finder.Gh.Detail
---@field body string
---@field closed? string
---@field merged? string
---@field base? string
---@field head? string
---@field mergeable? string
---@field additions? integer nil when the host reports no line totals (GitLab)
---@field deletions? integer
---@field files integer
---@field checks? Beast.Finder.Gh.Checks
---@field pipeline? string GitLab: status of the head pipeline ("passed", "failed", ...)
---@field reviewers? string[]
---@field assignees? string[]
---@field milestone? string
---@field conversation Beast.Finder.Gh.ConversationEntry[] oldest first

local DETAIL_FIELDS = {
	pr = "body,comments,reviews,statusCheckRollup,mergeable,baseRefName,headRefName,additions,deletions,changedFiles,closedAt,mergedAt",
	issue = "body,comments,closedAt",
}

local CHECK_PASSED = { SUCCESS = true, NEUTRAL = true, SKIPPED = true }
local CHECK_FAILED = { FAILURE = true, ERROR = true, TIMED_OUT = true, CANCELLED = true, ACTION_REQUIRED = true, STARTUP_FAILURE = true }

---@param kind Beast.Finder.Gh.Kind
---@param raw table decoded `gh pr|issue view --json` output
---@return Beast.Finder.Gh.Detail
function M.normalize_detail(kind, raw)
	local checks = { passed = 0, failed = 0, pending = 0 }
	for _, check in ipairs(raw.statusCheckRollup or {}) do
		-- a CheckRun reports `conclusion` (empty while running), a commit status reports `state`
		local verdict = (check.conclusion or check.state or ""):upper()
		if CHECK_PASSED[verdict] then
			checks.passed = checks.passed + 1
		elseif CHECK_FAILED[verdict] then
			checks.failed = checks.failed + 1
		else
			checks.pending = checks.pending + 1
		end
	end

	local conversation = {}
	for _, c in ipairs(raw.comments or {}) do
		conversation[#conversation + 1] = { author = c.author and c.author.login, body = c.body or "", created = c.createdAt or "" }
	end
	for _, r in ipairs(raw.reviews or {}) do
		-- a bare "commented" review with no text adds nothing next to its inline comments
		local verdict = r.state ~= "COMMENTED" and r.state or nil
		if (r.body or "") ~= "" or verdict then
			conversation[#conversation + 1] = { author = r.author and r.author.login, body = r.body or "", created = r.submittedAt or "", state = verdict }
		end
	end
	table.sort(conversation, function(a, b)
		return a.created < b.created
	end)

	return {
		body = raw.body or "",
		closed = raw.closedAt,
		merged = raw.mergedAt,
		base = raw.baseRefName,
		head = raw.headRefName,
		mergeable = raw.mergeable,
		additions = raw.additions or 0,
		deletions = raw.deletions or 0,
		files = raw.changedFiles or 0,
		checks = checks,
		conversation = conversation,
	}
end

--- Fetch what the preview pane needs beyond the search result. `cb` runs on the main loop, also after
--- `kill()`; callers that cancel must ignore it.
---@param item Beast.Finder.Gh.Item
---@param cb fun(result: { detail?: Beast.Finder.Gh.Detail, error?: string })
---@return Beast.Finder.Gh.Handle
function M.detail(item, cb)
	local proc = vim.system({
		"gh",
		item.kind == "pr" and "pr" or "issue",
		"view",
		tostring(item.number),
		"--repo",
		item.host .. "/" .. item.repo,
		"--json",
		DETAIL_FIELDS[item.kind],
	}, { text = true }, function(res)
		vim.schedule(function()
			if res.code ~= 0 then
				cb({ error = (res.stderr or ""):match("[^\r\n]+") or ("gh exited with code " .. res.code) })
				return
			end
			local ok, raw = pcall(vim.json.decode, res.stdout or "", { luanil = { object = true, array = true } })
			if not ok or type(raw) ~= "table" then
				cb({ error = "unexpected response from GitHub" })
				return
			end
			cb({ detail = M.normalize_detail(item.kind, raw) })
		end)
	end)
	return {
		kill = function()
			pcall(proc.kill, proc, 15)
		end,
	}
end

return M
