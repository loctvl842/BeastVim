local uv = vim.uv or vim.loop

local M = {}

---@return string? cmd, string[] args
local function find_cmd(cwd)
	if vim.fn.executable("fd") == 1 then
		return "fd", { "--type", "f", "--hidden", "--exclude", ".git", ".", cwd }
	elseif vim.fn.executable("rg") == 1 then
		return "rg", { "--files", "--hidden", "--glob", "!.git", cwd }
	elseif vim.fn.executable("find") == 1 then
		return "find", { cwd, "-type", "f", "-not", "-path", "*/.git/*" }
	end
	return nil, {}
end

---@param filter Beast.Finder.Filter
---@param cb fun(item: Beast.Finder.Item|nil) nil signals completion
function M.get(filter, cb)
	local cmd, args = find_cmd(filter.cwd)
	if not cmd then
		vim.schedule(function()
			vim.notify("beast.finder: no file-find binary (fd, rg, find)", vim.log.levels.WARN)
			cb(nil)
		end)
		return
	end

	local cwd = filter.cwd
	-- Ensure cwd ends with / for reliable prefix stripping
	local cwd_prefix = cwd:sub(-1) == "/" and cwd or (cwd .. "/")

	local idx = 0
	local buf = ""
	local stdout = uv.new_pipe(false)

	--- Build a relative path from an absolute one without vim.fn (safe in libuv callbacks)
	local function make_rel(path)
		if path:sub(1, #cwd_prefix) == cwd_prefix then
			return path:sub(#cwd_prefix + 1)
		end
		return path
	end

	--- Normalize path to absolute without vim.fn
	local function make_abs(path)
		if path:sub(1, 1) == "/" then
			return path
		end
		return cwd_prefix .. path
	end

	local handle
	handle = uv.spawn(cmd, { args = args, stdio = { nil, stdout, nil } }, function(code)
		stdout:close()
		handle:close()
		-- Flush any remaining content without a trailing newline
		if buf ~= "" then
			local path = vim.trim(buf)
			if path ~= "" then
				idx = idx + 1
				local abs = make_abs(path)
				local rel = make_rel(abs)
				local item = { idx = idx, score = 0, text = rel, file = abs, cwd = cwd }
				vim.schedule(function()
					cb(item)
				end)
			end
		end
		vim.schedule(function()
			cb(nil)
		end)
	end)

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
				local abs = make_abs(path)
				local rel = make_rel(abs)
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

M.async = true

return M
