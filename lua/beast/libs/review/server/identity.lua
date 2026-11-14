-- The {port, token} a working directory last served on. Claude Code re-dials
-- the ws://127.0.0.1:<port> and token it first connected with and never
-- rescans lock files, so a restarted Neovim only gets its session back by
-- coming up on the same address. The token is a secret: 0600 file in a 0700
-- dir, same as the lock file.

local uv = vim.uv or vim.loop

local M = {}

---@class Beast.Review.Identity
---@field port integer
---@field token string

---@return string
function M.dir()
	return vim.fs.normalize(vim.fn.stdpath("state") .. "/beast/review")
end

---@param cwd string
---@return string
function M.path(cwd)
	return ("%s/%s.json"):format(M.dir(), vim.fn.sha256(cwd):sub(1, 16))
end

---@param cwd string
---@return Beast.Review.Identity?
function M.load(cwd)
	local f = io.open(M.path(cwd), "rb")
	if not f then
		return nil
	end
	local body = f:read("*a")
	f:close()
	local ok, data = pcall(vim.json.decode, body)
	if not ok or type(data) ~= "table" then
		return nil
	end
	local port, token = data.port, data.token
	if type(port) ~= "number" or port % 1 ~= 0 or port < 1 or port > 65535 then
		return nil
	end
	if type(token) ~= "string" or not token:match("^%x+$") or #token ~= 32 then
		return nil
	end
	return { port = port, token = token }
end

--- Write atomically (temp file + rename).
---@param cwd string
---@param port integer
---@param token string
---@return boolean ok, string? err
function M.save(cwd, port, token)
	local made, merr = pcall(vim.fn.mkdir, M.dir(), "p", tonumber("700", 8))
	if not made then
		return false, tostring(merr)
	end
	local path = M.path(cwd)
	local tmp = path .. ".tmp"
	uv.fs_unlink(tmp)
	local fd, err = uv.fs_open(tmp, "wx", tonumber("600", 8))
	if not fd then
		return false, err
	end
	local _, werr = uv.fs_write(fd, vim.json.encode({ port = port, token = token }))
	uv.fs_close(fd)
	if werr then
		uv.fs_unlink(tmp)
		return false, werr
	end
	local renamed, rerr = uv.fs_rename(tmp, path)
	if not renamed then
		uv.fs_unlink(tmp)
		return false, rerr
	end
	return true
end

return M
