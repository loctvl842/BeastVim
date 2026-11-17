--- Everything that talks to the `glab` CLI for the GitLab finder sources.
--- Responses are normalized into the same item, file, commit and detail shapes the GitHub sources use
--- (see `gh/api.lua`), so no other module sees raw GitLab JSON.
local pager = require("beast.libs.finder.source.pager")

---@class Beast.Finder.Gl.Api
local M = {}

M.PER_PAGE = pager.PER_PAGE

local JSON = { luanil = { object = true, array = true } }

-- A request that gets no answer (a stalled connection) must not leave the picker on its spinner for good.
local TIMEOUT_MS = 30000

-- ---------------------------------------------------------------------------
-- Requests
-- ---------------------------------------------------------------------------

--- The project path as GitLab wants it inside a URL: every "/" is "%2F".
---@param path string "group/subgroup/name"
---@return string
function M.project_id(path)
	return (path:gsub("/", "%%2F"))
end

---@class Beast.Finder.Gl.Response
---@field body? any decoded JSON
---@field headers table<string, string> lowercase names
---@field error? Beast.Finder.Gh.Error

--- Split `glab api --include` output into the status line, headers and body.
---@param stdout string
---@return integer? status
---@return table<string, string> headers
---@return string body
local function split(stdout)
	local from, to = stdout:find("\r?\n\r?\n")
	local head = from and stdout:sub(1, from - 1) or ""
	local body = to and stdout:sub(to + 1) or stdout
	if not head:match("^HTTP/") then
		return nil, {}, stdout
	end
	local headers = {}
	for line in vim.gsplit(head, "\r?\n") do
		local name, value = line:match("^([^:%s]+):%s*(.-)%s*$")
		if name then
			headers[name:lower()] = value
		end
	end
	return tonumber(head:match("^HTTP/%S+ (%d+)")), headers, body
end

--- Seconds until a rate limit lifts, from the headers GitLab sends with the refusal.
---@param headers table<string, string>
---@return integer?
local function reset_in(headers)
	local retry = tonumber(headers["retry-after"])
	if retry then
		return math.max(1, retry)
	end
	local reset = tonumber(headers["ratelimit-reset"])
	return reset and math.max(1, reset - os.time()) or nil
end

---@param body any decoded error body
---@return string?
local function api_message(body)
	if type(body) ~= "table" then
		return nil
	end
	local msg = body.message or body.error
	if type(msg) == "table" then
		msg = vim.inspect(msg):gsub("%s+", " ")
	end
	return type(msg) == "string" and msg or nil
end

---@param res vim.SystemCompleted
---@param status? integer
---@param headers table<string, string>
---@param body string
---@param host string
---@return Beast.Finder.Gh.Error
local function classify(res, status, headers, body, host)
	local err = res.stderr or ""
	local lower = err:lower()
	status = status or tonumber(err:match("HTTP (%d%d%d)"))
	local ok, decoded = pcall(vim.json.decode, body, JSON)
	local msg = ok and api_message(decoded) or nil

	-- vim.system kills the process and reports 124 when `timeout` runs out
	if res.code == 124 then
		return { kind = "network", message = "GitLab did not answer in time" }
	end
	if status == 401 then
		return { kind = "auth", message = ("GitLab login expired, run `glab auth login --hostname %s`"):format(host) }
	end
	if status == 404 then
		return { kind = "not_found", message = "project not found or no access to it" }
	end
	if status == 429 or lower:find("rate limit", 1, true) then
		local secs = reset_in(headers)
		return { kind = "rate_limit", message = "GitLab rate limit reached" .. (secs and (", resets in %ds"):format(secs) or "") }
	end
	if lower:find("no such host", 1, true) or lower:find("connection refused", 1, true) or lower:find("i/o timeout", 1, true) then
		return { kind = "network", message = "cannot reach " .. host }
	end
	if msg then
		return { kind = "other", message = msg }
	end
	local first = err:match("[^\r\n]*%S[^\r\n]*")
	return { kind = "other", message = first and vim.trim(first) or ("glab exited with code " .. tostring(res.code)) }
end

---@param res vim.SystemCompleted
---@param host string
---@return Beast.Finder.Gl.Response
local function parse_response(res, host)
	local status, headers, body = split(res.stdout or "")
	if res.code ~= 0 then
		return { headers = headers, error = classify(res, status, headers, body, host) }
	end
	local ok, decoded = pcall(vim.json.decode, body, JSON)
	if not ok or type(decoded) ~= "table" then
		return { headers = headers, error = { kind = "other", message = "unexpected response from GitLab" } }
	end
	return { headers = headers, body = decoded }
end

--- One GET through `glab api`. `cb` runs on the main loop, also after the process was killed.
---@param host string
---@param path string below `/api/v4/`
---@param fields? table<string, string|integer> query parameters
---@param cb fun(res: Beast.Finder.Gl.Response)
---@return vim.SystemObj
local function request(host, path, fields, cb)
	local cmd = { "glab", "api", "-X", "GET", "--hostname", host, "--include", path }
	local keys = vim.tbl_keys(fields or {})
	table.sort(keys)
	for _, key in ipairs(keys) do
		vim.list_extend(cmd, { "-f", key .. "=" .. tostring(fields[key]) })
	end
	return vim.system(cmd, { text = true, timeout = TIMEOUT_MS }, function(res)
		vim.schedule(function()
			cb(parse_response(res, host))
		end)
	end)
end

--- Several requests at once; `kill` stops all of them.
---@param procs vim.SystemObj[]
---@return Beast.Finder.Gh.Handle
local function handle_of(procs)
	return {
		kill = function()
			for _, proc in ipairs(procs) do
				pcall(proc.kill, proc, 15)
			end
		end,
	}
end

-- ---------------------------------------------------------------------------
-- Repo detection and pre-flight
-- ---------------------------------------------------------------------------

---@param cwd string
---@return Beast.Git.Remote?
function M.repo(cwd)
	return Git.remote("gitlab", cwd)
end

--- Can a search run here? Returns the remote, or nil plus the reason to show the user.
---@param cwd string
---@return Beast.Git.Remote?
---@return string? err
function M.check(cwd)
	if vim.fn.executable("glab") ~= 1 then
		return nil, "GitLab CLI (glab) is not installed"
	end
	local repo = M.repo(cwd)
	if not repo then
		-- a remote on a host nobody told us is GitLab is the likely cause on a self-hosted server
		for _, remote in ipairs(require("beast.libs.git.remote").list(cwd)) do
			if not remote.provider then
				return nil, ("%s is not known as a GitLab server. Add it to the git remote hosts setting."):format(remote.host)
			end
		end
		return nil, "No GitLab remote found for this directory"
	end
	local res = vim.system({ "glab", "auth", "status", "--hostname", repo.host }, { text = true }):wait(5000)
	if res.code ~= 0 then
		return nil, ("Run `glab auth login --hostname %s` first"):format(repo.host)
	end
	return repo
end

-- ---------------------------------------------------------------------------
-- Search
-- ---------------------------------------------------------------------------

---@param raw table a label of a list response: a name, or an object with `with_labels_details`
---@return Beast.Finder.Gh.Label
local function normalize_label(raw)
	if type(raw) == "string" then
		return { name = raw, color = "888888" }
	end
	return { name = raw.name, color = (raw.color or "#888888"):gsub("^#", "") }
end

---@param kind Beast.Finder.Gl.Kind
---@param raw table one element of a list response
---@param host string
---@return Beast.Finder.Gh.Item
function M.normalize(kind, raw, host)
	local is_mr = kind == "mr"
	local state ---@type Beast.Finder.Gh.State
	if raw.state == "merged" then
		state = "merged"
	elseif raw.state == "closed" or raw.state == "locked" then
		state = "closed"
	else
		state = is_mr and raw.draft and "draft" or "open"
	end
	local ref = (is_mr and "!" or "#") .. raw.iid
	local labels = {}
	for _, label in ipairs(raw.labels or {}) do
		labels[#labels + 1] = normalize_label(label)
	end
	return {
		text = ("%s %s"):format(ref, raw.title or ""),
		kind = is_mr and "pr" or "issue",
		provider = "gitlab",
		ref = ref,
		state = state,
		number = raw.iid,
		title = raw.title or "",
		author = raw.author and raw.author.username or nil,
		labels = labels,
		url = raw.web_url,
		-- "group/sub/project!12": everything before the reference is the project
		repo = raw.references and raw.references.full and raw.references.full:gsub("[!#]%d+$", "") or "",
		host = host,
		created = raw.created_at,
		updated = raw.updated_at,
		comments = raw.user_notes_count or 0,
		body = raw.description,
	}
end

---@type table<string, string> logged-in username by host, kept for the session
local me_cache = {}

--- The username `@me` stands for on `host`.
---@param host string
---@param cb fun(name?: string, err?: Beast.Finder.Gh.Error)
---@return Beast.Finder.Gh.Handle
function M.me(host, cb)
	if me_cache[host] then
		cb(me_cache[host])
		return { kill = function() end }
	end
	return handle_of({
		request(host, "user", nil, function(res)
			if res.error then
				return cb(nil, res.error)
			end
			local name = res.body.username
			me_cache[host] = name
			cb(name)
		end),
	})
end

--- Forget the usernames looked up so far (for tests).
function M.reset()
	me_cache = {}
end

---@param params table<string, string>
---@return boolean
local function wants_me(params)
	for _, value in pairs(params) do
		if value == "@me" then
			return true
		end
	end
	return false
end

--- Run one search. `cb` is called on the main loop, also after `kill()` (with an error result);
--- callers that cancel must ignore it.
---@param kind Beast.Finder.Gl.Kind
---@param project string path of the project to search
---@param params table<string, string> from `gl/query.parse`
---@param host string
---@param cb fun(result: Beast.Finder.Gh.Result)
---@return Beast.Finder.Gh.Handle
function M.search(kind, project, params, host, cb)
	local procs, killed = {}, false

	local function list(fields)
		fields = vim.tbl_extend("keep", fields, {
			per_page = M.PER_PAGE,
			with_labels_details = "true",
			order_by = "created_at",
			sort = "desc",
		})
		local path = ("projects/%s/%s"):format(M.project_id(project), kind == "mr" and "merge_requests" or "issues")
		procs[#procs + 1] = request(host, path, fields, function(res)
			if res.error then
				return cb({ error = res.error })
			end
			local items = {}
			for i, raw in ipairs(res.body) do
				items[i] = M.normalize(kind, raw, host)
			end
			local total = tonumber(res.headers["x-total"])
			-- GitLab leaves the total out of very large sets; a next page still says there is more
			if not total then
				total = (res.headers["x-next-page"] or "") ~= "" and #items + 1 or #items
			end
			cb({ items = items, total = total })
		end)
	end

	if not wants_me(params) then
		list(vim.deepcopy(params))
	else
		local pending = M.me(host, function(name, err)
			if killed then
				return
			end
			if err then
				return cb({ error = err })
			end
			local fields = {}
			for key, value in pairs(params) do
				fields[key] = value == "@me" and name or value
			end
			list(fields)
		end)
		procs[#procs + 1] = { kill = pending.kill }
	end

	return {
		kill = function()
			killed = true
			for _, proc in ipairs(procs) do
				pcall(proc.kill, proc, 15)
			end
		end,
	}
end

--- Does `name` exist as a user on `host`? Explains an empty search (GitLab answers an unknown
--- username with an empty list, not an error).
---@param host string
---@param name string
---@param cb fun(exists: boolean)
---@return Beast.Finder.Gh.Handle
function M.user_exists(host, name, cb)
	return handle_of({
		request(host, "users", { username = name }, function(res)
			-- when the check itself fails the user is given the benefit of the doubt
			cb(res.error ~= nil or #res.body > 0)
		end),
	})
end

---@param item Beast.Finder.Gh.Item
---@param sha string
---@return string
function M.commit_url(item, sha)
	return ("https://%s/%s/-/commit/%s"):format(item.host, item.repo, sha)
end

-- ---------------------------------------------------------------------------
-- Files and commits (drill-down)
-- ---------------------------------------------------------------------------

--- Lines a patch adds and removes. GitLab sends the hunks only, so every `+`/`-` line counts.
---@param patch string
---@return integer additions
---@return integer deletions
local function count_changes(patch)
	local additions, deletions = 0, 0
	for line in vim.gsplit(patch, "\n", { plain = true }) do
		local c = line:sub(1, 1)
		if c == "+" then
			additions = additions + 1
		elseif c == "-" then
			deletions = deletions + 1
		end
	end
	return additions, deletions
end

---@param raw table one element of `merge_requests/:iid/diffs` or `repository/commits/:sha/diff`
---@return Beast.Finder.Gh.File
function M.normalize_file(raw)
	local status = "modified"
	if raw.new_file then
		status = "added"
	elseif raw.deleted_file then
		status = "removed"
	elseif raw.renamed_file then
		status = "renamed"
	end
	-- a diff GitLab left out (too large, collapsed, binary) comes empty
	local patch = (raw.diff ~= nil and raw.diff ~= "" and not raw.too_large and not raw.collapsed) and raw.diff or nil
	local additions, deletions = 0, 0
	if patch then
		additions, deletions = count_changes(patch)
	end
	return {
		path = raw.new_path,
		previous = raw.renamed_file and raw.old_path or nil,
		status = status,
		additions = additions,
		deletions = deletions,
		patch = patch,
	}
end

---@param raw table one element of `merge_requests/:iid/commits`
---@return Beast.Finder.Gh.Commit
function M.normalize_commit(raw)
	return {
		sha = raw.id,
		short = raw.short_id,
		subject = raw.title or "",
		message = raw.message or raw.title or "",
		author = raw.author_name or "",
		date = raw.created_at or "",
	}
end

--- Read a list endpoint of a project page by page (see `pager`).
---@generic T
---@param host string
---@param path string
---@param normalize fun(raw: table): T
---@param cb fun(result: Beast.Finder.Pager.Result)
---@return Beast.Finder.Gh.Handle
local function pages(host, path, normalize, cb)
	return pager.collect(function(page, done)
		return request(host, path, { per_page = pager.PER_PAGE, page = page }, function(res)
			if res.error then
				return done({ error = res.error })
			end
			done({ list = res.body })
		end)
	end, normalize, cb)
end

---@param item Beast.Finder.Gh.Item
---@param tail string
---@return string
local function project_path(item, tail)
	return ("projects/%s/%s"):format(M.project_id(item.repo), tail)
end

--- The files a merge request changes. `cb` runs on the main loop, also after `kill()`; callers that cancel must ignore it.
---@param item Beast.Finder.Gh.Item the merge request
---@param cb fun(result: Beast.Finder.Gh.FilesResult)
---@return Beast.Finder.Gh.Handle
function M.files(item, cb)
	return pages(item.host, project_path(item, ("merge_requests/%d/diffs"):format(item.number)), M.normalize_file, function(result)
		cb({ files = result.items, truncated = result.truncated, error = result.error })
	end)
end

--- The commits of a merge request, oldest first (the order the GitHub api uses; GitLab answers newest first).
---@param item Beast.Finder.Gh.Item the merge request
---@param cb fun(result: Beast.Finder.Gh.CommitsResult)
---@return Beast.Finder.Gh.Handle
function M.commits(item, cb)
	return pages(item.host, project_path(item, ("merge_requests/%d/commits"):format(item.number)), M.normalize_commit, function(result)
		local commits ---@type Beast.Finder.Gh.Commit[]?
		if result.items then
			commits = {}
			for i = #result.items, 1, -1 do
				commits[#commits + 1] = result.items[i]
			end
		end
		cb({ commits = commits, truncated = result.truncated, error = result.error })
	end)
end

--- The files one commit changed. The message is not fetched: the commit list already holds it.
---@param item Beast.Finder.Gh.Item the merge request (for the project)
---@param sha string
---@param cb fun(result: Beast.Finder.Gh.CommitDetailResult)
---@return Beast.Finder.Gh.Handle
function M.commit(item, sha, cb)
	return pages(item.host, project_path(item, ("repository/commits/%s/diff"):format(sha)), M.normalize_file, function(result)
		if result.error then
			return cb({ error = result.error })
		end
		cb({ detail = { message = "", files = result.items, truncated = result.truncated or false } })
	end)
end

-- ---------------------------------------------------------------------------
-- Detail (preview pane)
-- ---------------------------------------------------------------------------

local PIPELINE_ACTIVE = { running = true, pending = true, created = true, preparing = true, waiting_for_resource = true, scheduled = true }

---@param status string GitLab pipeline status
---@return string
local function pipeline_text(status)
	local words = status:gsub("_", " ")
	if status == "success" then
		return "✓ passed"
	elseif status == "failed" then
		return "✗ failed"
	elseif PIPELINE_ACTIVE[status] then
		return "● " .. words
	end
	return words
end

---@param users? table[]
---@return string[]
local function usernames(users)
	local names = {}
	for _, user in ipairs(users or {}) do
		names[#names + 1] = user.username
	end
	return names
end

---@param kind Beast.Finder.Gl.Kind
---@param raw table the merge request or issue
---@param notes table[] its notes, oldest first
---@return Beast.Finder.Gh.Detail
function M.normalize_detail(kind, raw, notes)
	local conversation = {}
	for _, note in ipairs(notes) do
		-- system notes are GitLab's own log lines ("added label ~bug"), not conversation
		if not note.system then
			conversation[#conversation + 1] = {
				author = note.author and note.author.username,
				body = note.body or "",
				created = note.created_at or "",
			}
		end
	end

	local detail = {
		body = raw.description or "",
		closed = raw.closed_at,
		merged = raw.merged_at,
		files = 0,
		assignees = usernames(raw.assignees),
		milestone = raw.milestone and raw.milestone.title or nil,
		conversation = conversation,
	}
	if kind == "mr" then
		detail.base = raw.target_branch
		detail.head = raw.source_branch
		-- "changes_count" is a string and reads "1000+" past the limit
		detail.files = tonumber(tostring(raw.changes_count or ""):match("%d+")) or 0
		detail.reviewers = usernames(raw.reviewers)
		if raw.head_pipeline and raw.head_pipeline.status then
			detail.pipeline = pipeline_text(raw.head_pipeline.status)
		end
		if raw.has_conflicts or raw.detailed_merge_status == "conflict" then
			detail.mergeable = "CONFLICTING"
		elseif raw.detailed_merge_status == "mergeable" then
			detail.mergeable = "MERGEABLE"
		end
	end
	return detail
end

--- Fetch what the preview pane needs beyond the list: the item and its conversation, two requests at once.
--- `cb` runs on the main loop, also after `kill()`; callers that cancel must ignore it.
---@param item Beast.Finder.Gh.Item
---@param cb fun(result: { detail?: Beast.Finder.Gh.Detail, error?: string })
---@return Beast.Finder.Gh.Handle
function M.detail(item, cb)
	local kind = item.kind == "pr" and "mr" or "issue"
	local base = ("projects/%s/%s/%d"):format(M.project_id(item.repo), kind == "mr" and "merge_requests" or "issues", item.number)
	local got = {} ---@type table<string, Beast.Finder.Gl.Response>
	local done = false

	local function finish()
		if done or not got.item or not got.notes then
			return
		end
		done = true
		local failed = got.item.error or got.notes.error
		if failed then
			return cb({ error = failed.message })
		end
		cb({ detail = M.normalize_detail(kind, got.item.body, got.notes.body) })
	end

	local procs = {
		request(item.host, base, nil, function(res)
			got.item = res
			finish()
		end),
		request(item.host, base .. "/notes", { order_by = "created_at", sort = "asc", per_page = M.PER_PAGE }, function(res)
			got.notes = res
			finish()
		end),
	}
	return handle_of(procs)
end

return M
