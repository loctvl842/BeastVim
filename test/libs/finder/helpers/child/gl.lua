-- Child-side half of the scripted `glab` / `git` helper for the GitLab finder specs: the generic
-- `vim.system` script of child/gh.lua plus builders for what `glab api --include` answers.
-- Published in the child as the global `GL` by `helpers/gl.lua`'s `install()`; the pure builders
-- (`http`, `http_error`, `mr`, `issue`, `diffs`, `commits`, `req`) are also required by the spec
-- process. Everything not defined here falls through to child/gh.lua. See helpers/gl.lua.
local gh = require("test.libs.finder.helpers.child.gh")

local M = setmetatable({}, { __index = gh })

---@param url? string remote URL of origin
function M.install(url)
	gh.install()
	gh.script["git -C"] = gh.ok("remote.origin.url " .. (url or "git@gitlab.com:o/n.git") .. "\n")
	gh.script["glab auth status"] = gh.ok("")
	require("beast.libs.finder.source.gl.api").reset()
end

---@param status string "200 OK"
---@param headers? table<string, string>
---@return string
local function head(status, headers)
	local lines = { "HTTP/2.0 " .. status }
	local names = vim.tbl_keys(headers or {})
	table.sort(names)
	for _, name in ipairs(names) do
		lines[#lines + 1] = name .. ": " .. headers[name]
	end
	return table.concat(lines, "\r\n") .. "\r\n\r\n"
end

--- A successful `glab api --include` answer.
---@param body table
---@param headers? table<string, string>
---@return vim.SystemCompleted
function M.http(body, headers)
	return gh.ok(head("200 OK", headers) .. vim.json.encode(body))
end

--- A failed one: exit 1, headers and the error body on stdout, glab's line on stderr.
---@param code integer HTTP status
---@param message string
---@param headers? table<string, string>
---@return vim.SystemCompleted
function M.http_error(code, message, headers)
	return {
		code = 1,
		stdout = head(code .. " Error", headers) .. vim.json.encode({ message = message }),
		stderr = ("glab: %s (HTTP %d)"):format(message, code),
	}
end

---@param iid integer
---@param title string
---@param extra? table
---@return table
function M.mr(iid, title, extra)
	return vim.tbl_extend("force", {
		iid = iid,
		title = title,
		state = "opened",
		draft = false,
		web_url = "https://gitlab.com/o/n/-/merge_requests/" .. iid,
		author = { username = "dao" },
		labels = {},
		user_notes_count = 0,
		references = { full = "o/n!" .. iid },
		created_at = "2026-11-10T10:00:00.000Z",
		updated_at = "2026-11-12T10:00:00.000Z",
		description = "desc " .. iid,
	}, extra or {})
end

---@param iid integer
---@param title string
---@param extra? table
---@return table
function M.issue(iid, title, extra)
	return vim.tbl_extend("force", {
		iid = iid,
		title = title,
		state = "opened",
		web_url = "https://gitlab.com/o/n/-/issues/" .. iid,
		author = { username = "dao" },
		labels = {},
		user_notes_count = 0,
		references = { full = "o/n#" .. iid },
		created_at = "2026-11-10T10:00:00.000Z",
		updated_at = "2026-11-12T10:00:00.000Z",
		description = "desc " .. iid,
	}, extra or {})
end

--- `n` changed files as `merge_requests/:iid/diffs` (and commit diffs) answer.
---@param n integer
---@param prefix? string
---@param from? integer
---@return table[]
function M.diffs(n, prefix, from)
	local out = {}
	for i = (from or 1), (from or 1) + n - 1 do
		local path = (prefix or "src/f") .. i .. ".lua"
		out[#out + 1] = {
			old_path = path,
			new_path = path,
			new_file = false,
			deleted_file = false,
			renamed_file = false,
			too_large = false,
			collapsed = false,
			diff = "@@ -1 +1,2 @@\n-old " .. i .. "\n+new " .. i .. "\n+extra\n",
		}
	end
	return out
end

--- `n` commits as `merge_requests/:iid/commits` answers them: NEWEST first.
---@param n integer
---@return table[]
function M.commits(n)
	local out = {}
	for i = n, 1, -1 do
		out[#out + 1] = {
			id = ("%08dabcdef0123456789abcdef0123456789"):format(i):sub(1, 40),
			short_id = ("%08d"):format(i),
			title = "Commit " .. i .. " subject",
			message = "Commit " .. i .. " subject\n\nBody of commit " .. i,
			author_name = "Author " .. i,
			created_at = "2026-11-1" .. (i % 9) .. "T17:00:00.000+07:00",
		}
	end
	return out
end

--- Shorthand for the request prefix of one endpoint.
---@param host string
---@param path string
---@return string
function M.req(host, path)
	return "glab api -X GET --hostname " .. host .. " --include " .. path
end

return M
