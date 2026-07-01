-- =========================================================================
-- Bench: Finder bigram index build + query AND throughput
-- =========================================================================
-- Builds the bigram index over the current repo (or $BENCH_ROOT) and times the
-- one-time build plus per-query AND. Conforms to the bench contract: final
-- stdout line begins with `BENCH `, includes name=grep-index, metrics, exit 0
-- PASS / 1 FAIL / 2 setup error.
--   Run as: nvim --clean --headless -l scripts/bench-grep.lua
-- =========================================================================

local QUERY_THRESHOLD_MS = 5 -- per-query AND
local MAX_FILE_SIZE = 1024 * 1024
local MAX_FILES = 90000

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local uv = vim.uv or vim.loop
local bigram = require("beast.libs.finder.source.live_grep.engine.bigram")
local extract = require("beast.libs.finder.source.live_grep.engine.extract")

if not bigram.available() then
	print("BENCH name=grep-index status=FAIL reason=no-ffi")
	vim.cmd("cquit 2")
end

local root = os.getenv("BENCH_ROOT") or uv.cwd()

-- Walk file list via rg (fast, respects .gitignore). Positional args drive grep.
local files = {}
local out = vim.fn.systemlist({ "rg", "--files", "--hidden", "--glob=!.git", root })
for _, f in ipairs(out) do
	files[#files + 1] = f
	if #files >= MAX_FILES then
		break
	end
end
if #files == 0 then
	print("BENCH name=grep-index status=FAIL reason=no-files")
	vim.cmd("cquit 2")
end

-- Build: read each file, feed bigrams. Oversize files are skipped (tracked).
local idx = bigram.new(#files)
local skipped = 0
local t0 = uv.hrtime()
for id, path in ipairs(files) do
	local fd = uv.fs_open(path, "r", 420)
	if fd then
		local st = uv.fs_fstat(fd)
		if st and st.size <= MAX_FILE_SIZE then
			local data = uv.fs_read(fd, st.size, 0)
			if data then
				idx:add(id - 1, data)
			end
		else
			skipped = skipped + 1
		end
		uv.fs_close(fd)
	end
end
local build_ms = (uv.hrtime() - t0) / 1e6

-- Query: average AND time + survivor count over a few literals.
local queries = { "error", "function", "return", "require\\(", "local" }
local total_ms, total_surv = 0, 0
for _, q in ipairs(queries) do
	local keys = extract.keys(q)
	local qt = uv.hrtime()
	local ids = idx:query(keys)
	total_ms = total_ms + (uv.hrtime() - qt) / 1e6
	total_surv = total_surv + (ids and #ids or #files)
end
local query_ms = total_ms / #queries
local avg_surv = math.floor(total_surv / #queries)

local s = idx:stats()
print(string.format("Files: %d (%d skipped)  columns=%d  ~%.1f MB", #files, skipped, s.columns, s.bytes / 1e6))
print(string.format("Build: %.1f ms   Query AND avg: %.3f ms   avg survivors: %d", build_ms, query_ms, avg_surv))

local status = query_ms < QUERY_THRESHOLD_MS and "PASS" or "FAIL"
print(
	string.format(
		"BENCH name=grep-index status=%s build=%.1fms query=%.3fms(<%dms) survivors=%d",
		status,
		build_ms,
		query_ms,
		QUERY_THRESHOLD_MS,
		avg_surv
	)
)

if status == "FAIL" then
	vim.cmd("cquit 1")
else
	vim.cmd("qall!")
end
