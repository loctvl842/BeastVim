-- =========================================================================
-- Spec-side scripted `glab` / `git` for the GitLab finder specs: everything of helpers/gh.lua
-- (set, hold, release, count, calls, killed, restore, ok, fail, json) plus builders for what
-- `glab api --include` answers. Stub lives in `helpers/child/gl.lua` (global `GL` in the child).
--
--   local gl = require("test.libs.finder.helpers.gl")
--   gl.install()                                          -- origin = git@gitlab.com:o/n.git, glab logged in
--   gl.set({ [gl.req("gitlab.com", "projects/o%2Fn/merge_requests")] = gl.http({ gl.mr(1, "t") }) })
--
-- API on top of gh's:
--   gl.install(url?)   `url` = remote URL of origin (default git@gitlab.com:o/n.git); also resets the gl api cache
--   gl.http(body, headers?)                  successful `glab api --include` answer
--   gl.http_error(code, message, headers?)   failed one
--   gl.mr(iid, title, extra?) gl.issue(iid, title, extra?) gl.diffs(n, prefix?, from?) gl.commits(n)  (newest first)
--   gl.req(host, path)                       request prefix of one endpoint
--   (gl.pr / gl.files / gl.reversed from gh are available too)
-- =========================================================================
local n = require("test.helper").n
local gh = require("test.libs.finder.helpers.gh")

local CHILD = "test.libs.finder.helpers.child.gl"
local builders = require(CHILD)

local M = setmetatable({}, { __index = gh })

M.http = builders.http
M.http_error = builders.http_error
M.mr = builders.mr
M.issue = builders.issue
M.diffs = builders.diffs
M.commits = builders.commits
M.req = builders.req

---@param url? string
function M.install(url)
	n.exec_lua(function(mod, ghmod, root, u)
		package.path = root .. "/?.lua;" .. package.path
		_G.GH = require(ghmod)
		_G.GL = require(mod)
		_G.GL.install(u)
	end, CHILD, "test.libs.finder.helpers.child.gh", vim.uv.cwd(), url)
end

return M
