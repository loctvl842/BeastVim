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

return M
