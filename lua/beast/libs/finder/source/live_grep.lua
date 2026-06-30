local uv = vim.uv or vim.loop
local bigram = require("beast.libs.finder.engine.bigram")
local config = require("beast.libs.finder.config")
local index = require("beast.libs.finder.engine.index")
local stats = require("beast.libs.finder.engine.stats")

---@class Beast.Finder.Source.LiveGrep: Beast.Finder.ASource
local M = {}

M.async = true
M.live = true
M.cmd = nil
M.args = {}

-- Maximum results to collect before stopping the process
local RESULT_LIMIT = 10000

-- Tracks an in-flight index build per cwd so we kick it off only once.
local building = nil

--- Resolve the bigram prefilter survivors for a query. Returns nil to grep the
--- whole tree (engine off/not ready/too many survivors); an (empty) list means
--- prune. Lazily kicks off a one-time background build on first open.
---@param pattern string
---@param cwd string
---@return string[]?
local function prefilter(pattern, cwd)
	local engine = config.engine
	if not (engine and engine.enabled and bigram.available()) then
		return nil
	end
	local idx = index.get(cwd)
	if not idx then
		if building ~= cwd then
			building = cwd
			index.build(cwd, { max_files = engine.max_files, max_file_size = engine.max_file_size }, function()
				building = nil
			end)
		end
		return nil
	end
	local files = idx:query(pattern)
	return files
end

-- Output parser for the active command: "ug" (custom --format) or "rg" (--json)
local parse_mode = "ug"

---@param text string search query
---@param cwd string
---@param files string[]? prefilter survivors; replace dir scan with these files
---@param text string search query
local function ensure_cmd(text)
	if vim.fn.executable("rg") == 1 then
		M.cmd = "rg"
		parse_mode = "rg"
		-- --json reports submatch byte offsets and the matched text, so the
		-- preview can highlight exactly what rg matched (same as ug) — no need
		-- to re-derive the literal from a regex query.
		M.base_args = {
			"--json",
			"--smart-case",
			"--hidden",
			"--glob=!.git",
			"--",
			text,
		}
	elseif vim.fn.executable("ug") == 1 then
		M.cmd = "ug"
		parse_mode = "ug"
		-- %d (match byte-length) prefixes %o (matched text) so we can split it
		-- off the front of %O (full line) without a delimiter that could collide
		-- with line content. The matched literal lets the preview highlight the
		-- exact text grep matched, even for regex/escaped queries like `require\(`.
		M.base_args = {
			"-r",
			"--format=%f:%n:%k:%d:%o%O%~",
			"--color=never",
			"--smart-case",
			"--hidden",
			"--exclude-dir=.git",
			"--tabs=1",
			"--",
			text,
		}
	else
		M.cmd = nil
		M.base_args = {}
	end
	M.args = M.base_args
end

-- Per-batch argv budget (bytes of survivor paths appended to base args). Kept
-- well under macOS ARG_MAX (~1 MB) so each `rg` spawn is safe; larger survivor
-- sets fan out into several batches.
local BATCH_BUDGET_BYTES = 256 * 1024
-- Cap concurrent `rg` processes so a pathological survivor set (tens of
-- thousands of files → many batches) can't fork-bomb the loop. ~CPU count.
local MAX_PARALLEL = math.max(2, math.min(8, (uv.available_parallelism and uv.available_parallelism()) or 4))

--- Split survivors into positional-arg batches, each under the argv budget.
--- `nil` survivors → a single whole-tree batch (`{ cwd }`). We batch and spawn
--- `rg` ourselves (instead of `xargs`) so every process is a direct child we
--- can kill outright on cancel — no orphaned grep keeps scanning after a
--- keystroke (xargs would reparent its rg child, leaving it running).
---@param cwd string
---@param survivors string[]?
---@return string[][] batches each a list of positional args for one rg run
local function batch_targets(cwd, survivors)
	if not survivors then
		return { { cwd } }
	end
	local batches, cur, size = {}, {}, 0
	for _, path in ipairs(survivors) do
		local plen = #path + 1
		if size + plen > BATCH_BUDGET_BYTES and #cur > 0 then
			batches[#batches + 1] = cur
			cur, size = {}, 0
		end
		cur[#cur + 1] = path
		size = size + plen
	end
	if #cur > 0 then
		batches[#batches + 1] = cur
	end
	return batches
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

--- Parse a grep output line into zero or more match records.
--- A record is `{ file, lnum, col (0-based byte), text (full line), match_text }`.
--- ug emits one match per output line; rg --json emits one object per matching
--- line that may contain several submatches (one record each).
---@param line string
---@return { file: string, lnum: integer, col: integer, text: string, match_text: string? }[]
local function parse_line(line)
	if parse_mode == "rg" then
		local ok, obj = pcall(vim.json.decode, line)
		if not ok or type(obj) ~= "table" or obj.type ~= "match" then
			return {}
		end
		local data = obj.data
		-- Non-UTF-8 content is reported as base64 `bytes` with no `text`; skip it.
		if not data or not data.lines or not data.lines.text or not data.path then
			return {}
		end
		local file = data.path.text
		local lnum = data.line_number
		if not file or not lnum then
			return {}
		end
		local text = data.lines.text:gsub("[\r\n]+$", "")
		local records = {}
		for _, sm in ipairs(data.submatches or {}) do
			local match_text = sm.match and sm.match.text
			if not match_text and sm.start and sm["end"] then
				match_text = text:sub(sm.start + 1, sm["end"])
			end
			records[#records + 1] = {
				file = file,
				lnum = lnum,
				col = sm.start or 0,
				text = text,
				match_text = match_text,
			}
		end
		return records
	end

	-- ug: file:line:col:matchlen:<matched_text><line_text>
	local file, lnum, col, mlen, rest = line:match("^(.+):(%d+):(%d+):(%d+):(.*)$")
	if not file then
		return {}
	end
	mlen = tonumber(mlen)
	-- `rest` is the matched text (mlen bytes) prepended to the full line text.
	return {
		{
			file = file,
			lnum = tonumber(lnum),
			col = tonumber(col) - 1,
			text = rest:sub(mlen + 1),
			match_text = rest:sub(1, mlen),
		},
	}
end

---@type { handle: uv.uv_process_t, stdout: uv.uv_pipe_t }[]
local current_procs = {}

---@param filter Beast.Finder.Filter
---@param cb fun(item: Beast.Finder.Item|nil) nil signals completion
function M.get(filter, cb)
	M.cancel()
	if filter.pattern == "" or filter.pattern == nil then
		vim.schedule(function()
			cb(nil)
		end)
		return
	end

	-- Bigram prefilter: empty survivor list = no file can match → done early.
	-- nil = grep the whole tree (engine off/not ready). Survivors → grep only
	-- those files (rg/ug still verifies, so results are byte-identical).
	local pf0 = uv.hrtime()
	local survivors = prefilter(filter.pattern, filter.cwd)
	local srec = stats.start(filter.pattern, survivors and #survivors or nil, (uv.hrtime() - pf0) / 1e6)
	if survivors and #survivors == 0 then
		stats.finish(srec, 0)
		vim.schedule(function()
			cb(nil)
		end)
		return
	end
	ensure_cmd(filter.pattern)
	if not M.cmd then
		vim.schedule(function()
			vim.notify("beast.finder: ug (ugrep) or rg (ripgrep) is required for live_grep", vim.log.levels.WARN)
			cb(nil)
		end)
		return
	end

	local cwd = filter.cwd
	local base_args = M.base_args
	local batches = batch_targets(cwd, survivors)

	-- TEMP: dump the resolved plan for inspection (overwrites each query).
	-- Per-cwd filename so different repos/sessions don't clobber each other.
	do
		local slug = cwd:gsub("[/\\:]", "_")
		local path = vim.fn.stdpath("state") .. "/beast-livegrep-cmd-" .. slug .. ".log"
		local f = io.open(path, "w")
		if f then
			local first = vim.deepcopy(base_args)
			vim.list_extend(first, batches[1] or {})
			f:write(
				("cwd=%s\nsurvivors=%s  batches=%d  parallel=%d\n%s %s\n"):format(
					cwd,
					survivors and #survivors or "full",
					#batches,
					MAX_PARALLEL,
					M.cmd,
					table.concat(first, " ")
				)
			)
			f:close()
		end
	end

	-- Shared state across all batch processes for this query.
	local idx = 0 -- result count (across batches)
	local done = false -- limit hit or all batches drained
	local next_batch = 1 -- cursor into `batches`
	local active = 0 -- running processes
	local pending = #batches -- processes not yet exited

	local function finish_all()
		if done then
			return
		end
		done = true
		stats.finish(srec, idx)
		vim.schedule(function()
			cb(nil)
		end)
	end

	---@param rec { file: string, lnum: integer, col: integer, text: string, match_text: string? }
	local function emit(rec)
		idx = idx + 1
		local abs = make_abs(cwd, rec.file)
		local rel = make_rel(cwd, abs)
		cb({
			idx = idx,
			score = 0,
			text = rel .. ":" .. rec.lnum .. ": " .. rec.text,
			file = abs,
			pos = { rec.lnum, rec.col },
			cwd = cwd,
			grep_text = rec.text,
			match_text = rec.match_text,
		})
	end

	local pump -- forward declaration (run_one schedules the next via pump)

	---@param positional string[] this batch's file/cwd args
	local function run_one(positional)
		local full = vim.deepcopy(base_args)
		vim.list_extend(full, positional)
		local stdout = assert(uv.new_pipe(false), "failed to create stdout pipe")
		local prev = "" -- partial trailing line for this process
		local proc = { stdout = stdout }
		current_procs[#current_procs + 1] = proc

		local handle
		handle = uv.spawn(M.cmd, {
			args = full,
			stdio = { nil, stdout, nil },
			hide = true,
		}, function()
			if not stdout:is_closing() then
				stdout:close()
			end
			if handle and not handle:is_closing() then
				handle:close()
			end
			-- Flush this process's final partial line.
			if not done and prev ~= "" then
				local line = vim.trim(prev)
				if line ~= "" then
					for _, rec in ipairs(parse_line(line)) do
						if idx < RESULT_LIMIT then
							emit(rec)
						end
					end
				end
			end
			active = active - 1
			pending = pending - 1
			if done then
				return
			end
			if pending == 0 then
				finish_all()
			else
				pump()
			end
		end)
		proc.handle = handle

		stdout:read_start(function(err, data)
			if err or not data or done then
				return
			end
			local from = 1
			while from <= #data do
				local nl = data:find("\n", from, true)
				if not nl then
					prev = prev .. data:sub(from)
					break
				end
				local line = data:sub(from, nl - 1)
				from = nl + 1
				if prev ~= "" then
					line = prev .. line
					prev = ""
				end
				if line:byte(#line) == 13 then
					line = line:sub(1, -2)
				end
				if line ~= "" then
					for _, rec in ipairs(parse_line(line)) do
						if idx >= RESULT_LIMIT then
							finish_all()
							M.cancel()
							return
						end
						emit(rec)
					end
				end
			end
		end)
	end

	-- Start batches up to the parallelism cap; each exit pumps the next.
	function pump()
		while not done and active < MAX_PARALLEL and next_batch <= #batches do
			local positional = batches[next_batch]
			next_batch = next_batch + 1
			active = active + 1
			run_one(positional)
		end
	end

	pump()
end

--- Cancel all running grep processes for the current query.
--- Each `rg` is a direct child, so killing its PID stops it outright — no
--- orphaned grep keeps scanning after the query is replaced.
function M.cancel()
	local procs = current_procs
	current_procs = {}
	for _, p in ipairs(procs) do
		if p.stdout then
			pcall(function()
				p.stdout:read_stop()
				if not p.stdout:is_closing() then
					p.stdout:close()
				end
			end)
		end
		if p.handle then
			pcall(function()
				p.handle:kill("SIGTERM")
				if not p.handle:is_closing() then
					p.handle:close()
				end
			end)
		end
	end
end

return M
