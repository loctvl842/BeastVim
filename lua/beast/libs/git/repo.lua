-- Async git command wrappers.
--
--   resolve(buf, cb)   → { toplevel, gitdir, relpath } | nil
--   get_base(ctx, cb)  → base_text:string | nil
--
-- Results from `resolve` are cached per buffer; the cache is busted by
-- `init.lua` on BufFilePost and on `detach`.

local uv = vim.uv or vim.loop

local M = {}

---@class Beast.Git.RepoCtx
---@field toplevel string Absolute path to the work tree root
---@field gitdir string Absolute path to .git (or worktree-redirected location)
---@field relpath string Path of `buf`'s file relative to `toplevel`

---@type table<integer, Beast.Git.RepoCtx | false>
local cache = {}

---@param buf integer
function M.invalidate(buf)
	cache[buf] = nil
end

---@param buf integer
---@param cb fun(ctx: Beast.Git.RepoCtx | nil)
function M.resolve(buf, cb)
	local hit = cache[buf]
	if hit ~= nil then
		vim.schedule(function()
			cb(hit or nil)
		end)
		return
	end

	local name = vim.api.nvim_buf_get_name(buf)
	if name == "" then
		cache[buf] = false
		vim.schedule(function()
			cb(nil)
		end)
		return
	end

	local real = uv.fs_realpath(name) or name
	local dir = vim.fs.dirname(real)

	vim.system({ "git", "-C", dir, "rev-parse", "--show-toplevel", "--absolute-git-dir" }, { text = true }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				cache[buf] = false
				return cb(nil)
			end
			local lines = vim.split(vim.trim(result.stdout or ""), "\n", { plain = true })
			if #lines < 2 then
				cache[buf] = false
				return cb(nil)
			end
			local toplevel, gitdir = lines[1], lines[2]
			if real:sub(1, #toplevel + 1) ~= toplevel .. "/" then
				cache[buf] = false
				return cb(nil)
			end
			local ctx = {
				toplevel = toplevel,
				gitdir = gitdir,
				relpath = real:sub(#toplevel + 2),
			}
			cache[buf] = ctx
			cb(ctx)
		end)
	end)
end

--- Fetch the HEAD version of `ctx.relpath`. Returns `""` for newly-tracked
--- files (matches gitsigns: every buffer line then renders as `add`).
---@param ctx Beast.Git.RepoCtx
---@param cb fun(base_text: string)
function M.get_base(ctx, cb)
	vim.system({ "git", "-C", ctx.toplevel, "show", "HEAD:" .. ctx.relpath }, { text = true }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				return cb("")
			end
			cb(result.stdout or "")
		end)
	end)
end

return M
