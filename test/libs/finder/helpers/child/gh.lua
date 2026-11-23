-- Child-side half of the scripted `gh` / `git` helper for the GitHub finder specs: vim.system answers
-- from a table keyed by a prefix of the command line (longest prefix wins), so nothing touches the
-- network. Loaded in the child Nvim by `helpers/gh.lua`'s `install()`, published as the global `GH`.
-- The pure builders (`ok`, `fail`, `pr`, `files`, `commits`, `reversed`) hold no state, so the spec
-- process requires this module directly for them. See helpers/gh.lua for the API.
local M = {}

M.calls = {} ---@type string[]
M.argvs = {} ---@type string[][] the same commands as raw argv
M.hold = {} ---@type string[] command prefixes whose answers wait until `release()`
local held = {} ---@type fun()[]
M.script = {} ---@type table<string, vim.SystemCompleted>

local orig_system, orig_executable
M.killed = 0 ---@type integer how many `kill()` calls reached a fake process

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

--- A list in the opposite order (the tests write commits newest first, the API answers oldest first).
---@generic T
---@param list T[]
---@return T[]
function M.reversed(list)
	local out = {}
	for i = #list, 1, -1 do
		out[#out + 1] = list[i]
	end
	return out
end

--- Stub `vim.system` and `vim.fn.executable`. Idempotent; resets calls, script and holds.
---@param opts? { bare?: boolean } `bare` leaves the script empty (no origin remote, no gh login)
function M.install(opts)
	if not orig_system then
		orig_system, orig_executable = vim.system, vim.fn.executable
	end
	require("beast.libs.git.remote").invalidate()
	M.calls, M.argvs, M.hold, held, M.killed = {}, {}, {}, {}, 0
	M.script = {}
	if not (opts and opts.bare) then
		M.script["git -C"] = M.ok("remote.origin.url git@github.com:o/n.git\n")
		M.script["gh auth token"] = M.ok("token\n")
	end
	vim.fn.executable = function()
		return 1
	end
	---@diagnostic disable-next-line: duplicate-set-field
	vim.system = function(cmd, _, on_exit)
		local line = table.concat(cmd, " ")
		M.calls[#M.calls + 1] = line
		M.argvs[#M.argvs + 1] = cmd
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
			kill = function()
				M.killed = M.killed + 1
			end,
		}
	end
end

--- Add or replace scripted answers.
---@param answers table<string, vim.SystemCompleted>
function M.set(answers)
	for prefix, answer in pairs(answers) do
		M.script[prefix] = answer
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
	if orig_system then
		vim.system, vim.fn.executable = orig_system, orig_executable
	end
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
