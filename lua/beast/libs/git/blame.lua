-- Async `git blame --incremental` wrapper.
--
-- run(ctx, opts, cb) spawns:
--   git -C <toplevel> blame --incremental
--     [--contents -]              when opts.contents (buffer modified)
--     [--ignore-whitespace]       when opts.ignore_whitespace
--     [-L <lnum>,+1]              when opts.lnum (single-line cursor blame)
--     [<revision>]                when opts.revision (reblame parent)
--     -- <relpath>
--
-- Output is the porcelain incremental format:
--
--   <40-hex-sha> <orig_lnum> <final_lnum> <size>
--   author <name>
--   author-mail <addr>
--   author-time <unix>
--   author-tz <zone>
--   committer <name>
--   ...
--   summary <subject>
--   previous <40-hex-sha> <relpath>     (optional)
--   boundary                            (optional, on first commit reached)
--   filename <relpath>
--
-- Commit metadata only appears on the first block for each sha; we dedup
-- via a `commits[sha]` table so subsequent blocks just reference it.
--
-- Untracked files: callers pass opts.untracked=true; we short-circuit and
-- synthesize a "Not Committed Yet" commit covering the requested range,
-- avoiding a git invocation that would just fail.

local M = {}

---@class Beast.Git.CommitInfo
---@field sha string 40-char hex
---@field abbrev_sha string First 8 chars
---@field author string
---@field author_mail string
---@field author_time integer Unix timestamp
---@field author_tz string e.g. "+0700"
---@field committer string
---@field committer_mail string
---@field committer_time integer
---@field committer_tz string
---@field summary string
---@field boundary? true Set when this is the first commit in the history

---@class Beast.Git.BlameInfo
---@field orig_lnum integer Line number in `commit`
---@field final_lnum integer Line number in the blamed revision
---@field commit Beast.Git.CommitInfo
---@field filename string Path at the time of `commit`
---@field previous_sha? string Parent commit (when blame can follow history further)
---@field previous_filename? string Path in the parent commit (rename-aware)

---@class Beast.Git.BlameOpts
---@field lnum? integer 1-based line to blame (omit = whole file)
---@field contents? string[] Buffer lines to feed via stdin (use when buffer is modified)
---@field ignore_whitespace? boolean
---@field revision? string Blame a specific revision (e.g. "<sha>^" to reblame parent)
---@field untracked? boolean Short-circuit: synthesize "Not Committed Yet" without spawning git

-- Synthetic placeholder for lines that haven't been committed (untracked
-- files, or modified lines surfaced via `--contents`). Mirrors gitsigns'
-- normalization so downstream formatters can branch cleanly.
local NOT_COMMITTED_SHA = string.rep("0", 40)
local NOT_COMMITTED_AUTHOR = "Not Committed Yet"
local NOT_COMMITTED_MAIL = "<not.committed.yet>"

---@param file string
---@return Beast.Git.CommitInfo
local function not_committed_commit(file)
	local time = os.time()
	return {
		sha = NOT_COMMITTED_SHA,
		abbrev_sha = NOT_COMMITTED_SHA:sub(1, 8),
		author = NOT_COMMITTED_AUTHOR,
		author_mail = NOT_COMMITTED_MAIL,
		author_time = time,
		author_tz = "+0000",
		committer = NOT_COMMITTED_AUTHOR,
		committer_mail = NOT_COMMITTED_MAIL,
		committer_time = time,
		committer_tz = "+0000",
		summary = "Version of " .. file,
	}
end

---@param file string
---@param start_lnum integer 1-based
---@param count integer
---@return table<integer, Beast.Git.BlameInfo>
---@return table<string, Beast.Git.CommitInfo>
local function synth_not_committed(file, start_lnum, count)
	local commit = not_committed_commit(file)
	local result = {}
	for i = 0, count - 1 do
		result[start_lnum + i] = {
			orig_lnum = 0,
			final_lnum = start_lnum + i,
			commit = commit,
			filename = file,
		}
	end
	return result, { [NOT_COMMITTED_SHA] = commit }
end

-- Parse one porcelain block starting at `lines[i]`. Returns the next index
-- to read (one past the terminating `filename` line). Mutates `commits`
-- and `result` in place.
---@param lines string[]
---@param i integer Index of the header line
---@param commits table<string, Beast.Git.CommitInfo>
---@param result table<integer, Beast.Git.BlameInfo>
---@return integer next_i
local function parse_block(lines, i, commits, result)
	local header = lines[i]
	local sha, orig_str, final_str, size_str = header:match("^(%x+) (%d+) (%d+) (%d+)$")
	if not sha then
		error(("git blame: bad header at line %d: %q"):format(i, header))
	end
	local orig_lnum = tonumber(orig_str)
	local final_lnum = tonumber(final_str)
	local size = tonumber(size_str)

	local commit = commits[sha] or {
		sha = sha,
		abbrev_sha = sha:sub(1, 8),
	}

	local previous_sha, previous_filename
	local filename

	i = i + 1
	while i <= #lines do
		local line = lines[i]
		if line:sub(1, 9) == "filename " then
			filename = line:sub(10)
			i = i + 1
			break
		elseif line:sub(1, 9) == "previous " then
			previous_sha, previous_filename = line:match("^previous (%x+) (.*)$")
		elseif line == "boundary" then
			commit.boundary = true
		else
			local key, value = line:match("^([^%s]+) (.*)$")
			if key then
				key = key:gsub("-", "_")
				if key:sub(-5) == "_time" then
					commit[key] = tonumber(value)
				else
					commit[key] = value
				end
			end
		end
		i = i + 1
	end

	-- git 2.41+: lines attributed to `--contents` are tagged with a
	-- synthetic author_mail; treat them as Not Committed Yet so the
	-- formatter picks the `_nc` branch.
	if commit.author_mail == "<external.file>" or commit.author_mail == "External file (--contents)" then
		commit.author = NOT_COMMITTED_AUTHOR
		commit.author_mail = NOT_COMMITTED_MAIL
		commit.committer = NOT_COMMITTED_AUTHOR
		commit.committer_mail = NOT_COMMITTED_MAIL
	end

	commits[sha] = commit

	for j = 0, size - 1 do
		result[final_lnum + j] = {
			orig_lnum = orig_lnum + j,
			final_lnum = final_lnum + j,
			commit = commit,
			filename = filename or "",
			previous_sha = previous_sha,
			previous_filename = previous_filename,
		}
	end

	return i
end

---@param stdout string
---@return table<integer, Beast.Git.BlameInfo>
---@return table<string, Beast.Git.CommitInfo>
function M._parse(stdout)
	local result = {}
	local commits = {}
	local lines = vim.split(stdout, "\n", { plain = true })
	-- Trailing empty line from final \n.
	if lines[#lines] == "" then
		lines[#lines] = nil
	end
	local i = 1
	while i <= #lines do
		i = parse_block(lines, i, commits, result)
	end
	return result, commits
end

--- Run git blame for `ctx`. Callback receives `(blame_by_lnum, commits_by_sha)`
--- on success, or `(nil, nil)` on git failure (stderr is logged).
---@param ctx Beast.Git.RepoCtx
---@param opts Beast.Git.BlameOpts
---@param cb fun(blame: table<integer, Beast.Git.BlameInfo>?, commits: table<string, Beast.Git.CommitInfo>?)
function M.run(ctx, opts, cb)
	opts = opts or {}

	if opts.untracked then
		local start = opts.lnum or 1
		local count = opts.lnum and 1 or (opts.contents and #opts.contents or 1)
		local r, c = synth_not_committed(ctx.relpath, start, count)
		vim.schedule(function()
			cb(r, c)
		end)
		return
	end

	local cmd = { "git", "-C", ctx.toplevel, "blame", "--incremental" }
	if opts.contents then
		cmd[#cmd + 1] = "--contents"
		cmd[#cmd + 1] = "-"
	end
	if opts.ignore_whitespace then
		cmd[#cmd + 1] = "--ignore-whitespace"
	end
	if opts.lnum then
		cmd[#cmd + 1] = "-L"
		cmd[#cmd + 1] = opts.lnum .. ",+1"
	end
	if opts.revision then
		cmd[#cmd + 1] = opts.revision
	end
	cmd[#cmd + 1] = "--"
	cmd[#cmd + 1] = ctx.relpath

	local stdin = opts.contents and table.concat(opts.contents, "\n") or nil

	vim.system(cmd, { text = true, stdin = stdin }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				return cb(nil, nil)
			end
			local ok, blame, commits = pcall(M._parse, result.stdout or "")
			if not ok then
				vim.notify("beast.libs.git.blame: parse error: " .. tostring(blame), vim.log.levels.WARN)
				return cb(nil, nil)
			end
			cb(blame, commits)
		end)
	end)
end

M._NOT_COMMITTED_SHA = NOT_COMMITTED_SHA

return M
