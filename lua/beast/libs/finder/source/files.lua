local uv = vim.uv or vim.loop

---@class Beast.Finder.Source.Files: Beast.Finder.ASource
local M = {}

M.live = false
M.async = true
M.cmd = nil
M.args = {}

local function ensure_cmd(cwd)
	if vim.fn.executable("fd") == 1 then
		M.cmd = "fd"
		M.args = { "--type", "f", "--hidden", "--exclude", ".git", ".", cwd }
	elseif vim.fn.executable("rg") == 1 then
		M.cmd = "rg"
		M.args = { "--files", "--hidden", "--glob", "!.git", "--glob", "!.git/**", cwd }
	elseif vim.fn.executable("find") == 1 then
		M.cmd = "find"
		M.args = { cwd, "-type", "f", "-not", "-path", "*/.git/*" }
	else
		M.cmd = nil
		M.args = {}
	end
end

--- Build a relative path from an absolute one without vim.fn (safe in libuv callbacks)
---@param cwd string
---@param path string
---@return string
local function make_rel(cwd, path)
	-- Ensure cwd ends with / for reliable prefix stripping
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
	-- Ensure cwd ends with / for reliable prefix stripping
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
	local buf = ""

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

			-- Flush any remaining content without a trailing newline
			if buf ~= "" then
				local path = vim.trim(buf)

				if path ~= "" then
					idx = idx + 1

					local abs = make_abs(cwd, path)
					local rel = make_rel(cwd, abs)
					local item = {
						idx = idx,
						score = 0,
						text = rel,
						file = abs,
						cwd = cwd,
					}

					vim.schedule(function()
						cb(item)
					end)
				end
			end

			vim.schedule(function()
				cb(nil)
			end)
		end),
		"failed to spawn " .. M.cmd
	)

	stdout:read_start(function(err, data)
		if err or not data then
			return
		end
		buf = buf .. data
		local batch = {}
		-- Split on newlines, keep partial last line in buf
		local lines = {}
		local pos = 1
		while true do
			local nl = buf:find("\n", pos, true)
			if not nl then
				break
			end
			lines[#lines + 1] = buf:sub(pos, nl - 1)
			pos = nl + 1
		end
		buf = buf:sub(pos)

		for _, line in ipairs(lines) do
			local path = vim.trim(line)
			if path ~= "" then
				idx = idx + 1
				local abs = make_abs(cwd, path)
				local rel = make_rel(cwd, abs)
				batch[#batch + 1] = { idx = idx, score = 0, text = rel, file = abs, cwd = cwd }
			end
		end

		if #batch > 0 then
			vim.schedule(function()
				for _, item in ipairs(batch) do
					cb(item)
				end
			end)
		end
	end)
end

return M
