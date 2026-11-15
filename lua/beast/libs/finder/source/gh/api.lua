--- Everything that talks to the `gh` CLI for the GitHub finder sources.
--- Search results are normalized into finder items here so no other module sees raw API JSON.

---@class Beast.Finder.Gh.Repo
---@field host string
---@field slug string "owner/name"

---@class Beast.Finder.Gh.Label
---@field name string
---@field color string hex without "#"

---@alias Beast.Finder.Gh.State "open"|"draft"|"merged"|"closed"|"not_planned"

---@class Beast.Finder.Gh.Item: Beast.Finder.Item
---@field kind Beast.Finder.Gh.Kind
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

---@class Beast.Finder.Gh.Error
---@field kind "not_found"|"rate_limit"|"auth"|"network"|"other"
---@field message string

---@class Beast.Finder.Gh.Result
---@field items? Beast.Finder.Gh.Item[]
---@field total? integer total matches on GitHub (may exceed #items)
---@field error? Beast.Finder.Gh.Error

---@class Beast.Finder.Gh.Handle
---@field kill fun()

---@class Beast.Finder.Gh.Api
local M = {}

M.PER_PAGE = 100

-- ---------------------------------------------------------------------------
-- Repo detection and pre-flight (local only, no network)
-- ---------------------------------------------------------------------------

--- Parse a git remote URL (https, ssh://, scp-like) into host and "owner/name".
---@param url string
---@return Beast.Finder.Gh.Repo?
function M.parse_remote(url)
	url = vim.trim(url)
	local host, path
	local rest = url:match("^%a[%w+.-]*://(.+)$")
	if rest then
		rest = rest:gsub("^[^/@]*@", "")
		host, path = rest:match("^([^/:]+):?%d*/(.+)$")
	else
		host, path = url:match("^[^@/]+@([^:/]+):(.+)$")
	end
	if not host then
		return nil
	end
	path = path:gsub("%.git$", ""):gsub("/+$", "")
	if not path:match("^[^/]+/[^/]+$") then
		return nil
	end
	return { host = host, slug = path }
end

---@param cwd string
---@return Beast.Finder.Gh.Repo?
function M.repo(cwd)
	local res = vim.system({ "git", "-C", cwd, "remote", "get-url", "origin" }, { text = true }):wait()
	if res.code ~= 0 then
		return nil
	end
	return M.parse_remote(res.stdout or "")
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
---@field truncated? boolean the pull request changes more files than `FILES_PAGES` pages hold
---@field error? Beast.Finder.Gh.Error

--- GitHub lists up to 3000 files; we ask for this many pages of `PER_PAGE` and say when there are more.
M.FILES_PAGES = 3

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

--- The files a pull request changes, read page by page. `cb` runs on the main loop, also after
--- `kill()`; callers that cancel must ignore it.
---@param item Beast.Finder.Gh.Item the pull request
---@param cb fun(result: Beast.Finder.Gh.FilesResult)
---@return Beast.Finder.Gh.Handle
function M.files(item, cb)
	local files, killed = {}, false
	local proc ---@type vim.SystemObj?

	local function fetch(page)
		proc = vim.system({
			"gh",
			"api",
			"-X",
			"GET",
			("repos/%s/pulls/%d/files"):format(item.repo, item.number),
			"--hostname",
			item.host,
			"-f",
			"per_page=" .. M.PER_PAGE,
			"-f",
			"page=" .. page,
		}, { text = true }, function(res)
			vim.schedule(function()
				if res.code ~= 0 then
					return cb({ error = classify(res) })
				end
				local ok, list = pcall(vim.json.decode, res.stdout or "", { luanil = { object = true, array = true } })
				if not ok or type(list) ~= "table" then
					return cb({ error = { kind = "other", message = "unexpected response from GitHub" } })
				end
				-- The page after the last one we keep only tells whether the list was cut short.
				if page > M.FILES_PAGES then
					return cb({ files = files, truncated = #list > 0 })
				end
				for _, raw in ipairs(list) do
					files[#files + 1] = M.normalize_file(raw)
				end
				if #list < M.PER_PAGE or killed then
					return cb({ files = files })
				end
				fetch(page + 1)
			end)
		end)
	end
	fetch(1)

	return {
		kill = function()
			killed = true
			if proc then
				pcall(proc.kill, proc, 15)
			end
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
---@field additions integer
---@field deletions integer
---@field files integer
---@field checks Beast.Finder.Gh.Checks
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
