local uv = vim.uv or vim.loop
local Queue = require("beast.libs.finder.queue")

---@class Beast.Finder.Source.Files: Beast.Finder.ASource
local M = {}

M.live = false
M.async = true
M.cmd = nil
M.args = {}

SUPPORTED = {
	{
		cmd = "fd",
		args = function(cwd)
      -- stylua: ignore
			return {
				"--type", "f",
				"--type", "l",
				"--color", "never",
				"--hidden",
				"--exclude", ".git",
				".",
				cwd,
			}
		end,
	},
	{
		cmd = "rg",
		args = function(cwd)
      -- stylua: ignore
			return {
				"--files",
				"--color", "never",
				"--no-messages",
				"--hidden",
				"--glob", "!.git",
				"--glob", "!.git/**",
				cwd,
			}
		end,
	},
	{
		cmd = "find",
		args = function(cwd)
      -- stylua: ignore
			return {
				cwd,
				"-type", "f",
				"-not", "-path", "*/.git/*",
			}
		end,
	},
}

local function ensure_cmd(cwd)
	for _, command in ipairs(SUPPORTED) do
		if vim.fn.executable(command.cmd) == 1 then
			M.cmd = command.cmd
			M.args = command.args(cwd)
			return
		end
	end

	M.cmd = nil
	M.args = {}
end

--- Build a relative path from an absolute one without vim.fn (safe in libuv callbacks)
---@param cwd string
---@param path string
---@return string
local function make_rel(cwd, path)
	local cwd_prefix = cwd:sub(-1) == "/" and cwd or (cwd .. "/")
	if path:sub(1, #cwd_prefix) == cwd_prefix then
		return path:sub(#cwd_prefix + 1)
	end
	return path
end

--- Normalize path to absolute without vim.fn
---@param cwd string
---@param path string
---@return string
local function make_abs(cwd, path)
	local cwd_prefix = cwd:sub(-1) == "/" and cwd or (cwd .. "/")
	if path:sub(1, 1) == "/" then
		return path
	end
	return cwd_prefix .. path
end

---@param filter Beast.Finder.Filter
---@param cb fun(item: Beast.Finder.Item|nil) nil signals completion
function M.get(filter, cb)
	ensure_cmd(filter.cwd)
	if not M.cmd then
		vim.schedule(function()
			vim.notify("beast.libs.finder: no file-find binary (fd, rg, find)", vim.log.levels.WARN)
			cb(nil)
		end)
		return
	end

	local cwd = filter.cwd
	local idx = 0
	local queue = Queue()
	local done = false

	local stdout = assert(uv.new_pipe(false), "failed to create stdout pipe")
	local handle

	---@type uv.spawn.options
	local spawn_opts = {
		args = M.args,
		stdio = { nil, stdout, nil },
		cwd = nil,
		env = nil,
		uid = nil,
		gid = nil,
		verbatim = false,
		detached = false,
		hide = true,
	}

	handle = assert(
		uv.spawn(M.cmd, spawn_opts, function()
			stdout:close()
			if handle and not handle:is_closing() then
				handle:close()
			end
			done = true
		end),
		"failed to spawn " .. M.cmd
	)

	local buf = ""

	stdout:read_start(function(err, data)
		if err or not data then
			return
		end
		queue:push(data)
	end)

	-- Process queue in a tight loop via vim.schedule polling
	-- This avoids vim.schedule per chunk while still being safe for cb()
	local function process()
		while not queue:empty() do
			local data = queue:pop()
			buf = buf .. data
			local pos = 1
			while true do
				local nl = buf:find("\n", pos, true)
				if not nl then
					break
				end
				local line = buf:sub(pos, nl - 1)
				pos = nl + 1
				local path = line
				if path ~= "" then
					idx = idx + 1
					local abs = make_abs(cwd, path)
					local rel = make_rel(cwd, abs)
					cb({ idx = idx, score = 0, text = rel, file = abs, cwd = cwd })
				end
			end
			buf = buf:sub(pos)
		end

		if done then
			-- Flush remaining partial line
			if buf ~= "" then
				local path = buf
				buf = ""

				idx = idx + 1
				local abs = make_abs(cwd, path)
				local rel = make_rel(cwd, abs)
				cb({ idx = idx, score = 0, text = rel, file = abs, cwd = cwd })
			end
			cb(nil)
		else
			vim.defer_fn(process, 1)
		end
	end

	vim.schedule(process)
end

return M
