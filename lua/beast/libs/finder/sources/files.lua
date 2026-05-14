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

	local idx = 0
	local buf = ""
	local stdout = uv.new_pipe(false)

	local handle
	handle = uv.spawn(cmd, { args = args, stdio = { nil, stdout, nil } }, function(code)
		stdout:close()
		handle:close()
		-- Flush any remaining content without a trailing newline
		if buf ~= "" then
			local path = vim.trim(buf)
			if path ~= "" then
				idx = idx + 1
				local abs = vim.fn.fnamemodify(path, ":p")
				local rel = path
				if abs:sub(1, #filter.cwd) == filter.cwd then
					rel = abs:sub(#filter.cwd + 2)
				end
				local item = { idx = idx, score = 0, text = rel, file = abs, cwd = filter.cwd }
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
				local abs = vim.fn.fnamemodify(path, ":p")
				local rel = path
				if abs:sub(1, #filter.cwd) == filter.cwd then
					rel = abs:sub(#filter.cwd + 2)
				end
				batch[#batch + 1] = { idx = idx, score = 0, text = rel, file = abs, cwd = filter.cwd }
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
