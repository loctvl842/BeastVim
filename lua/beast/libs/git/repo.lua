-- Async git command wrappers.
--
--   resolve(buf, cb)        → { toplevel, gitdir, relpath } | nil
--   get_base(ctx, cb)       → index_text:string ("" if untracked)
--   get_head(ctx, cb)       → head_text:string  ("" if not in HEAD)
--   get_path_data(ctx, cb)  → { rel_path, mode_bits, eol } | nil
--
-- Results from `resolve` are cached per buffer; the cache is busted by
-- `init.lua` on BufFilePost and on `detach`. Base/head/path_data are
-- re-fetched on demand by the diff scheduler.

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

--- Fetch the index version of `ctx.relpath` (i.e. the staging area).
--- Returns `""` for untracked files (matches mini.diff/gitsigns: every buffer
--- line then renders as `add`).
---@param ctx Beast.Git.RepoCtx
---@param cb fun(base_text: string)
function M.get_base(ctx, cb)
	vim.system({ "git", "-C", ctx.toplevel, "show", ":" .. ctx.relpath }, { text = true }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				return cb("")
			end
			cb(result.stdout or "")
		end)
	end)
end

--- Fetch the HEAD version of `ctx.relpath`. Used to compute the staged diff
--- (HEAD vs index). Returns `""` for files not in HEAD.
---@param ctx Beast.Git.RepoCtx
---@param cb fun(head_text: string)
function M.get_head(ctx, cb)
	vim.system({ "git", "-C", ctx.toplevel, "show", "HEAD:" .. ctx.relpath }, { text = true }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				return cb("")
			end
			cb(result.stdout or "")
		end)
	end)
end

---@class Beast.Git.PathData
---@field rel_path string Path relative to repo toplevel, as Git sees it
---@field mode_bits string Octal mode bits as reported by `ls-files --format`
---@field eol "lf"|"crlf"|"mixed"|"none"|"" EOL style of the index version

--- Fetch path metadata Git needs to construct a valid stage patch:
---   - canonical relpath (matters when CWD ≠ toplevel)
---   - mode bits ("100644", "100755", ...) for the patch header
---   - EOL style so we know whether to emit `\r\n` in patch body
--- Borrows the `--format` approach from mini.diff (cleaner than parsing
--- separate `ls-files -s` + `attr` calls).
---@param ctx Beast.Git.RepoCtx
---@param cb fun(data: Beast.Git.PathData | nil)
function M.get_path_data(ctx, cb)
	local args = {
		"git",
		"-C",
		ctx.toplevel,
		"ls-files",
		"-z",
		"--full-name",
		"--format=%(objectmode) %(eolinfo:index) %(path)",
		"--",
		ctx.relpath,
	}
	vim.system(args, { text = true }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				return cb(nil)
			end
			local out = (result.stdout or ""):gsub("[\n%z]+$", "")
			local mode_bits, eol, rel_path = string.match(out, "^(%d+)%s+(%S+)%s+(.*)$")
			if not mode_bits then
				return cb(nil)
			end
			cb({ rel_path = rel_path, mode_bits = mode_bits, eol = eol })
		end)
	end)
end

--- Mark an untracked file as intent-to-add so it shows up in the index with
--- the empty blob. Required before staging a hunk on a new file, because
--- `git apply --cached` needs an index entry to patch against.
---@param ctx Beast.Git.RepoCtx
---@param cb fun(ok: boolean, stderr: string)
function M.intent_to_add(ctx, cb)
	vim.system({ "git", "-C", ctx.toplevel, "add", "--intent-to-add", "--", ctx.relpath }, { text = true }, function(result)
		vim.schedule(function()
			cb(result.code == 0, result.stderr or "")
		end)
	end)
end

return M
