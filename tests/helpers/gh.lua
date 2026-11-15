-- =========================================================================
-- A scripted `gh` / `git` for the GitHub finder tests: vim.system answers from a table keyed by a
-- prefix of the command line, so nothing touches the network.
--
--   local gh = dofile("tests/helpers/gh.lua")
--   gh.script["gh api -X GET search/issues"] = gh.ok(json)
--   gh.install() ... gh.restore()
-- =========================================================================
local M = {}

M.calls = {} ---@type string[]
M.hold = {} ---@type string[] command prefixes whose answers wait until `release()`
local held = {} ---@type fun()[]
M.script = {} ---@type table<string, vim.SystemCompleted>

local orig_system, orig_executable

---@param stdout string
---@return vim.SystemCompleted
function M.ok(stdout)
	return { code = 0, stdout = stdout, stderr = "" }
end

---@param stderr string
---@return vim.SystemCompleted
function M.fail(stderr)
	return { code = 1, stdout = "", stderr = stderr }
end

--- One search/issues element for a pull request.
---@param number integer
---@param title string
---@return table
function M.pr(number, title)
	return {
		number = number,
		title = title,
		state = "open",
		html_url = "https://github.com/o/n/pull/" .. number,
		repository_url = "https://api.github.com/repos/o/n",
		pull_request = {},
		user = { login = "me" },
		labels = {},
		comments = 0,
	}
end

--- `n` changed files named `<prefix>1.lua` ... as `pulls/{n}/files` returns them.
---@param n integer
---@param prefix? string
---@param from? integer
---@return table[]
function M.files(n, prefix, from)
	local out = {}
	for i = (from or 1), (from or 1) + n - 1 do
		out[#out + 1] = {
			filename = (prefix or "src/f") .. i .. ".lua",
			status = "modified",
			additions = i,
			deletions = 1,
			patch = "@@ -1 +1 @@\n-old " .. i .. "\n+new " .. i,
		}
	end
	return out
end

--- `n` commits as `pulls/{n}/commits` returns them (oldest first).
---@param n integer
---@param from? integer
---@return table[]
function M.commits(n, from)
	local out = {}
	for i = (from or 1), (from or 1) + n - 1 do
		out[#out + 1] = {
			sha = ("%07dabcdef0123456789abcdef0123456789"):format(i):sub(1, 40),
			commit = {
				message = "Commit " .. i .. " subject\n\nBody of commit " .. i,
				author = { name = "Author " .. i, date = "2026-11-1" .. (i % 9) .. "T10:00:00Z" },
			},
			author = { login = "dev" .. i },
		}
	end
	return out
end

function M.install()
	orig_system, orig_executable = vim.system, vim.fn.executable
	M.calls, M.script = {}, {
		["git -C"] = M.ok("git@github.com:o/n.git\n"),
		["gh auth token"] = M.ok("token\n"),
	}
	vim.fn.executable = function()
		return 1
	end
	---@diagnostic disable-next-line: duplicate-set-field
	vim.system = function(cmd, _, on_exit)
		local line = table.concat(cmd, " ")
		M.calls[#M.calls + 1] = line
		local res
		local best = -1
		for prefix, answer in pairs(M.script) do
			if line:sub(1, #prefix) == prefix and #prefix > best then
				res, best = answer, #prefix
			end
		end
		res = res or M.fail("unscripted: " .. line)
		if on_exit then
			local function answer()
				vim.schedule(function()
					on_exit(res)
				end)
			end
			local waits = false
			for _, prefix in ipairs(M.hold) do
				waits = waits or line:sub(1, #prefix) == prefix
			end
			if waits then
				held[#held + 1] = answer
			else
				answer()
			end
		end
		return {
			wait = function()
				return res
			end,
			kill = function() end,
		}
	end
end

--- Deliver the answers held back by `hold`.
function M.release()
	local pending = held
	held = {}
	for _, answer in ipairs(pending) do
		answer()
	end
end

function M.restore()
	M.hold, held = {}, {}
	vim.system, vim.fn.executable = orig_system, orig_executable
end

--- How many recorded commands start with `prefix`.
---@param prefix string
---@return integer
function M.count(prefix)
	local n = 0
	for _, line in ipairs(M.calls) do
		if line:sub(1, #prefix) == prefix then
			n = n + 1
		end
	end
	return n
end

return M
