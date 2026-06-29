local uv = vim.uv or vim.loop
local bigram = require("beast.libs.finder.engine.bigram")
local config = require("beast.libs.finder.config")
local index = require("beast.libs.finder.engine.index")

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
	if files and #files > engine.max_survivors then
		return nil -- too many to pass as args; full scan is cheaper than xargs here
	end
	return files
end

-- Output parser for the active command: "ug" (custom --format) or "rg" (--json)
local parse_mode = "ug"

---@param text string search query
---@param cwd string
---@param files string[]? prefilter survivors; replace dir scan with these files
local function ensure_cmd(text, cwd, files)
	if vim.fn.executable("ug") == 1 then
		M.cmd = "ug"
		parse_mode = "ug"
		-- %d (match byte-length) prefixes %o (matched text) so we can split it
		-- off the front of %O (full line) without a delimiter that could collide
		-- with line content. The matched literal lets the preview highlight the
		-- exact text grep matched, even for regex/escaped queries like `require\(`.
		M.args = {
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
	elseif vim.fn.executable("rg") == 1 then
		M.cmd = "rg"
		parse_mode = "rg"
		-- --json reports submatch byte offsets and the matched text, so the
		-- preview can highlight exactly what rg matched (same as ug) — no need
		-- to re-derive the literal from a regex query.
		M.args = {
			"--json",
			"--smart-case",
			"--hidden",
			"--glob=!.git",
			"--",
			text,
		}
	else
		M.cmd = nil
		M.args = {}
		return
	end
	-- Search either the prefiltered file list or the whole tree. Bigram
	-- survivors only prune, so grep over them is byte-identical to a full scan.
	if files then
		vim.list_extend(M.args, files)
	else
		M.args[#M.args + 1] = cwd
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

---@type uv.uv_process_t|nil
local current_handle = nil
---@type uv.uv_pipe_t|nil
local current_stdout = nil

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
	local survivors = prefilter(filter.pattern, filter.cwd)
	if survivors and #survivors == 0 then
		vim.schedule(function()
			cb(nil)
		end)
		return
	end
	ensure_cmd(filter.pattern, filter.cwd, survivors)
	if not M.cmd then
		vim.schedule(function()
			vim.notify("beast.finder: ug (ugrep) or rg (ripgrep) is required for live_grep", vim.log.levels.WARN)
			cb(nil)
		end)
		return
	end

	local cwd = filter.cwd
	local idx = 0
	local completed = false
	local prev = "" -- partial line from previous chunk
	local stdout = assert(uv.new_pipe(false), "failed to create stdout pipe")
	current_stdout = stdout

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

	local handle
	handle = uv.spawn(M.cmd, spawn_opts, function()
		if not stdout:is_closing() then
			stdout:close()
		end
		if handle and not handle:is_closing() then
			handle:close()
		end
		current_handle = nil
		current_stdout = nil

		-- If limit was already reached, don't signal completion again
		if completed then
			return
		end
		completed = true

		-- Flush remaining partial line
		if prev ~= "" then
			local line = vim.trim(prev)
			prev = ""
			if line ~= "" then
				for _, rec in ipairs(parse_line(line)) do
					if idx < RESULT_LIMIT then
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
				end
			end
		end
		vim.schedule(function()
			cb(nil)
		end)
	end)

	current_handle = handle

	stdout:read_start(function(err, data)
		if err or not data then
			return
		end

		-- Parse lines directly from each chunk, tracking partial trailing line
		local batch = {}
		local from = 1
		while from <= #data do
			local nl = data:find("\n", from, true)
			if not nl then
				-- No more newlines — save as partial line for next chunk
				if prev ~= "" then
					prev = prev .. data:sub(from)
				else
					prev = data:sub(from)
				end
				break
			end

			local line = data:sub(from, nl - 1)
			from = nl + 1
			if prev ~= "" then
				line = prev .. line
				prev = ""
			end

			-- Strip \r if present
			if line:byte(#line) == 13 then
				line = line:sub(1, -2)
			end

			if line ~= "" then
				for _, rec in ipairs(parse_line(line)) do
					idx = idx + 1
					if idx > RESULT_LIMIT then
						completed = true
						M.cancel()
						for _, item in ipairs(batch) do
							cb(item)
						end
						vim.schedule(function()
							cb(nil)
						end)
						return
					end
					local abs = make_abs(cwd, rec.file)
					local rel = make_rel(cwd, abs)
					batch[#batch + 1] = {
						idx = idx,
						score = 0,
						text = rel .. ":" .. rec.lnum .. ": " .. rec.text,
						file = abs,
						pos = { rec.lnum, rec.col },
						cwd = cwd,
						grep_text = rec.text,
						match_text = rec.match_text,
					}
				end
			end
		end

		if #batch > 0 then
			for _, item in ipairs(batch) do
				cb(item)
			end
		end
	end)
end

--- Cancel any running grep process
function M.cancel()
	if current_stdout then
		pcall(function()
			current_stdout:read_stop()
			current_stdout:close()
		end)
		current_stdout = nil
	end
	if current_handle then
		pcall(function()
			current_handle:kill("SIGTERM")
			current_handle:close()
		end)
		current_handle = nil
	end
end

return M
