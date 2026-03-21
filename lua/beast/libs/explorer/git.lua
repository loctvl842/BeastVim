--- Pure async git-status fetcher.
--- No knowledge of windows, buffers, or records — just paths and XY codes.
---
--- Usage:
---   Git.fetch(cwd, function(status)
---     -- status: table<string, string>  path (abs) → "XY" porcelain code
---   end)

---@class Beast.Explorer.Git.State
---@field status  table<string, string>  abs_path → "XY"
---@field last    number                 os.time() of last completed fetch
---@field tick    integer                monotonic counter to discard stale results

local M = {}

local uv = vim.uv or vim.loop

local TTL = 10 -- seconds before cache is considered stale

---@type table<string, Beast.Explorer.Git.State>
local cache = {}

--- Return the git root containing `path`, or nil when not in a repo.
---@param path string
---@return string|nil
local function git_root(path)
	local result = vim.fn.system({ "git", "-C", path, "rev-parse", "--show-toplevel" })
    -- stylua: ignore
    if vim.v.shell_error ~= 0 then return nil end
	return vim.trim(result)
end

--- Asynchronously fetch `git status --porcelain` for the repo that contains
--- `cwd`.  Calls `on_done(status)` on the main loop thread when ready.
--- Results are cached for `TTL` seconds; stale ticks are silently dropped.
---@param cwd     string
---@param on_done fun(status: table<string, string>)
function M.fetch(cwd, on_done)
	local root = git_root(cwd)
	if not root then
		on_done({})
		return
	end

	local state = cache[root]
	if state and (os.time() - state.last) < TTL then
		on_done(state.status)
		return
	end

	-- Ensure a state slot exists and bump the tick
	cache[root] = cache[root] or { status = {}, last = 0, tick = 0 }
	state = cache[root]
	state.tick = state.tick + 1
	local tick = state.tick

	local output = ""
	local stdout = assert(uv.new_pipe())
	local handle ---@type uv.uv_process_t

	handle = uv.spawn("git", {
		args = {
			"--no-pager",
			"--no-optional-locks",
			"status",
			"--porcelain=v1",
			"--ignored=matching",
			"-z",
		},
		cwd = root,
		stdio = { nil, stdout, nil },
		hide = true,
	}, function()
		handle:close()
	end)

	if not handle then
		on_done({})
		return
	end

	stdout:read_start(function(err, data)
		assert(not err, err)
		if data then
			output = output .. data
			return
		end
		stdout:close()

        -- A newer tick superseded us — discard
        -- stylua: ignore
        if not cache[root] or cache[root].tick ~= tick then return end

		-- Parse NUL-separated porcelain output
		local status = {} ---@type table<string, string>
		for _, line in ipairs(vim.split(output, "\0", { plain = true })) do
			local xy, file = line:match("^(..) (.+)$")
			if xy and file then
				status[root .. "/" .. file] = xy
			end
		end

		cache[root].status = status
		cache[root].last = os.time()

		vim.schedule(function()
			on_done(status)
		end)
	end)
end

--- Invalidate any cached root that is an ancestor of (or equal to) `path`.
--- Call this after file-system mutations inside the repo.
---@param path string
function M.invalidate(path)
	for root in pairs(cache) do
		if path == root or path:find(root .. "/", 1, true) == 1 then
			cache[root].last = 0
		end
	end
end

return M
