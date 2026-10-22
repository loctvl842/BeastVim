-- Discovery file: Claude Code scans <config>/ide/*.lock to find editors.
-- The auth token lives here, so the file is created 0600 inside a 0700 dir.

local uv = vim.uv or vim.loop

local M = {}

local IDE_NAME = "Neovim"

---@return string
function M.dir()
	local base = vim.env.CLAUDE_CONFIG_DIR
	if base and base ~= "" then
		return vim.fs.normalize(base .. "/ide")
	end
	return vim.fs.normalize("~/.claude/ide")
end

--- 128-bit token as 32 lowercase hex chars from the OS CSPRNG. There is
--- deliberately no weaker fallback: a guessable token is worse than no server.
---@return string? token, string? err
function M.token()
	local ok, bytes = pcall(uv.random, 16)
	if not ok or type(bytes) ~= "string" or #bytes ~= 16 then
		return nil, "no secure random source available"
	end
	return (bytes:gsub(".", function(c)
		return ("%02x"):format(c:byte())
	end))
end

---@param port integer
---@return string
function M.path(port)
	return ("%s/%d.lock"):format(M.dir(), port)
end

--- Write the lock file atomically (temp file + rename).
---@param port integer
---@param token string
---@param workspace_folders string[]
---@return string? path, string? err
function M.write(port, token, workspace_folders)
	local dir = M.dir()
	local made, merr = pcall(vim.fn.mkdir, dir, "p", tonumber("700", 8))
	if not made then
		return nil, tostring(merr)
	end

	local path = M.path(port)
	local tmp = path .. ".tmp"
	-- Never write through a pre-existing temp file (stale, or a planted symlink).
	uv.fs_unlink(tmp)
	local fd, err = uv.fs_open(tmp, "wx", tonumber("600", 8))
	if not fd then
		return nil, err
	end
	local body = vim.json.encode({
		pid = uv.os_getpid(),
		workspaceFolders = workspace_folders,
		ideName = IDE_NAME,
		transport = "ws",
		authToken = token,
	})
	local _, werr = uv.fs_write(fd, body)
	uv.fs_close(fd)
	if werr then
		uv.fs_unlink(tmp)
		return nil, werr
	end
	local renamed, rerr = uv.fs_rename(tmp, path)
	if not renamed then
		uv.fs_unlink(tmp)
		return nil, rerr
	end
	return path
end

---@param path? string
function M.remove(path)
	if path then
		uv.fs_unlink(path)
	end
end

--- Remove lock files left behind by crashed Neovim instances. Only files this
--- lib could have written (ideName == "Neovim") whose process is gone are
--- touched; another IDE's lock file is never deleted.
function M.cleanup_stale()
	local dir = M.dir()
	for _, file in ipairs(vim.fn.glob(dir .. "/*.lock", false, true)) do
		local f = io.open(file, "rb")
		local body = f and f:read("*a")
		if f then
			f:close()
		end
		local ok, data = pcall(vim.json.decode, body or "")
		if ok and type(data) == "table" and data.ideName == IDE_NAME and type(data.pid) == "number" then
			-- Signal 0 probes existence without delivering anything. Only ESRCH
			-- means "gone"; EPERM means a live process we may not signal.
			local alive, _, code = uv.kill(data.pid, 0)
			if not alive and code == "ESRCH" then
				uv.fs_unlink(file)
			end
		end
	end
end

return M
