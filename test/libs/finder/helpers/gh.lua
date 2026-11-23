-- =========================================================================
-- Spec-side scripted `gh` / `git` for the GitHub finder specs: vim.system in the child answers from
-- a table keyed by a prefix of the command line (longest prefix wins), so nothing touches the
-- network. The stub lives in `helpers/child/gh.lua` (global `GH` in the child); this module drives it.
--
--   local gh = require("test.libs.finder.helpers.gh")
--   gh.install()                                         -- origin = git@github.com:o/n.git, gh logged in
--   gh.set({ ["gh api -X GET search/issues"] = gh.json({ total_count = 1, items = { gh.pr(1, "t") } }) })
--   ... F.open("gh_pr") ...
--   t.eq(1, gh.count("gh api -X GET search/issues"))
--   gh.restore()                                         -- optional, a fresh child drops the stub anyway
--
-- API:
--   gh.install(opts?)       stub vim.system / executable in the child; `{ bare = true }` leaves the script
--                           empty (no remote, no login). Call after F.setup(), again to reset calls/script.
--   gh.set(answers)         add or replace scripted answers: { [command prefix] = vim.SystemCompleted }
--   gh.hold(prefixes)       delay the (async) answers of commands starting with these prefixes ...
--   gh.release()            ... until released
--   gh.count(prefix)        how many recorded commands start with `prefix`
--   gh.calls()              string[] of every command run
--   gh.argvs()             string[][] of every command run, one element per argument
--   gh.killed()             how many `kill()` calls reached a fake process
--   gh.restore()
-- Pure builders (usable on the spec side, same as in the child):
--   gh.ok(stdout) gh.fail(stderr) gh.json(value)  answers (`json` = ok(vim.json.encode(value)))
--   gh.pr(number, title) gh.files(n, prefix?, from?) gh.commits(n, from?) gh.reversed(list)
-- =========================================================================
local n = require("test.helper").n

local CHILD = "test.libs.finder.helpers.child.gh"
local builders = require(CHILD)

local M = {}

M.ok = builders.ok
M.fail = builders.fail
M.pr = builders.pr
M.files = builders.files
M.commits = builders.commits
M.reversed = builders.reversed

---@param value any
---@return vim.SystemCompleted
function M.json(value)
	return builders.ok(vim.json.encode(value))
end

---@param opts? { bare?: boolean }
function M.install(opts)
	n.exec_lua(function(mod, root, o)
		package.path = root .. "/?.lua;" .. package.path
		_G.GH = require(mod)
		_G.GH.install(o)
	end, CHILD, vim.uv.cwd(), opts)
end

---@param answers table<string, vim.SystemCompleted>
function M.set(answers)
	n.exec_lua(function(a)
		_G.GH.set(a)
	end, answers)
end

---@param prefixes string[]
function M.hold(prefixes)
	n.exec_lua(function(p)
		_G.GH.hold = p
	end, prefixes)
end

function M.release()
	n.exec_lua(function()
		_G.GH.release()
	end)
end

---@param prefix string
---@return integer
function M.count(prefix)
	return n.exec_lua(function(p)
		return _G.GH.count(p)
	end, prefix)
end

---@return string[]
function M.calls()
	return n.exec_lua(function()
		return _G.GH.calls
	end)
end

---@return string[][]
function M.argvs()
	return n.exec_lua(function()
		return _G.GH.argvs
	end)
end

---@return integer
function M.killed()
	return n.exec_lua(function()
		return _G.GH.killed
	end)
end

function M.restore()
	n.exec_lua(function()
		_G.GH.restore()
	end)
end

return M
