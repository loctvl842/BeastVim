-- Remotes of a project and the hosting providers behind them.
--
--   parse(url)             → { host, slug } | nil
--   provider_of(host)      → "github" | "gitlab" | nil
--   list(root)             → Beast.Git.Remote[]   (cached per root)
--   remote(provider, root) → Beast.Git.Remote | nil   (`origin` preferred)
--   providers(root)        → string[]   (sorted, e.g. { "github", "gitlab" })
--   has_provider(name, root) → boolean
--   invalidate(root?)      → drop one root (or all) from the cache
--
-- The first lookup for a root runs one `git config --get-regexp` synchronously;
-- the cache is dropped on FocusGained so a `git remote add` made in another
-- terminal shows up when focus returns.

local config = require("beast.libs.git.config")

local M = {}

---@class Beast.Git.Remote
---@field name string Remote name ("origin")
---@field url string
---@field host string
---@field slug string "owner/name" ("group/subgroup/name" on GitLab)
---@field provider? string "github"|"gitlab"|nil when the host is not a known provider

--- Substring of the host that identifies each provider (keeps GitHub Enterprise working).
local PROVIDERS = { "github", "gitlab" }

---@type table<string, Beast.Git.Remote[]>
local cache = {}
local watching = false

--- Parse a git remote URL (https, ssh://, scp-like) into host and "owner/name" (nested GitLab groups keep every segment).
---@param url string
---@return { host: string, slug: string }?
function M.parse(url)
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
	if not path:match("^[^/]+/.+$") then
		return nil
	end
	return { host = host, slug = path }
end

--- `config.remote.hosts` wins over the substring rule.
---@param host string
---@return string?
function M.provider_of(host)
	local mapped = config.remote.hosts[host]
	if mapped then
		return mapped
	end
	host = host:lower()
	for _, provider in ipairs(PROVIDERS) do
		if host:find(provider, 1, true) then
			return provider
		end
	end
end

---@param root? string
---@return string
local function resolve_root(root)
	return root or Util.root()
end

---@param root? string
function M.invalidate(root)
	if root then
		cache[root] = nil
	else
		cache = {}
	end
end

local function watch()
	if watching then
		return
	end
	watching = true
	vim.api.nvim_create_autocmd("FocusGained", {
		group = vim.api.nvim_create_augroup("BeastGitRemote", { clear = true }),
		callback = function()
			M.invalidate()
		end,
	})
end

--- Every remote of the project with a parsable URL, in git config order.
---@param root? string defaults to the current project root
---@return Beast.Git.Remote[]
function M.list(root)
	root = resolve_root(root)
	local hit = cache[root]
	if hit then
		return hit
	end
	watch()

	local remotes = {} ---@type Beast.Git.Remote[]
	local res = vim.system({ "git", "-C", root, "config", "--get-regexp", [[^remote\..*\.url$]] }, { text = true }):wait()
	if res.code == 0 then
		for line in vim.gsplit(res.stdout or "", "\n", { plain = true }) do
			local name, url = line:match("^remote%.(.+)%.url (.+)$")
			local parsed = url and M.parse(url)
			if parsed then
				remotes[#remotes + 1] = {
					name = name,
					url = url,
					host = parsed.host,
					slug = parsed.slug,
					provider = M.provider_of(parsed.host),
				}
			end
		end
	end
	cache[root] = remotes
	return remotes
end

--- The remote hosted on `provider`; `origin` wins when several match.
---@param provider string
---@param root? string
---@return Beast.Git.Remote?
function M.remote(provider, root)
	local found ---@type Beast.Git.Remote?
	for _, r in ipairs(M.list(root)) do
		if r.provider == provider then
			if r.name == "origin" then
				return r
			end
			found = found or r
		end
	end
	return found
end

---@param root? string
---@return string[]
function M.providers(root)
	local seen, ret = {}, {}
	for _, r in ipairs(M.list(root)) do
		if r.provider and not seen[r.provider] then
			seen[r.provider] = true
			ret[#ret + 1] = r.provider
		end
	end
	table.sort(ret)
	return ret
end

---@param name string
---@param root? string
---@return boolean
function M.has_provider(name, root)
	return M.remote(name, root) ~= nil
end

return M
