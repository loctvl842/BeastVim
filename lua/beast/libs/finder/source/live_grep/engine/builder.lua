-- Off-main-thread bigram index build.
--
-- Runs inside a headless `nvim` subprocess (see scripts/build-finder-index.lua):
-- walks the repo once via `rg --files`, reads every file into the bigram bitset
-- in a tight blocking loop, then serializes the result to a binary file the
-- editor loads with one `ffi.copy`. There's no time budget here — this isn't the
-- editor's loop, so blocking is free and the ~minutes-long scan never touches UI.
--
-- Kept free of `arg`/env parsing (the thin script wrapper handles that) so the
-- build routine stays directly unit-testable.

local uv = vim.uv or vim.loop
local bigram = require("beast.libs.finder.source.live_grep.engine.bigram")
local serialize = require("beast.libs.finder.source.live_grep.engine.serialize")

local M = {}

--- List files under root (rg honors .gitignore). Caps at max_files.
---@param root string
---@param max_files integer
---@return string[]
local function list_files(root, max_files)
	local out = vim.fn.systemlist({ "rg", "--files", "--hidden", "--glob=!.git", root })
	if vim.v.shell_error ~= 0 then
		return {}
	end
	if #out > max_files then
		for i = #out, max_files + 1, -1 do
			out[i] = nil
		end
	end
	return out
end

--- Read one file and feed its bigrams; oversize files are skipped (rg still
--- searches them directly, so they're never dropped from results).
---@param bg Beast.Finder.Bigram
---@param path string
---@param id integer 0-based file id
---@param max_file_size integer
local function scan_file(bg, path, id, max_file_size)
	local fd = uv.fs_open(path, "r", 420)
	if not fd then
		return
	end
	local st = uv.fs_fstat(fd)
	if st and st.size <= max_file_size then
		local data = uv.fs_read(fd, st.size, 0)
		if data then
			bg:add(id, data)
		end
	end
	uv.fs_close(fd)
end

--- Build an index for `root` and serialize it to `out`. Returns false (with a
--- reason) when there's nothing to build or the write fails — the caller treats
--- that as "no index" and falls back to a full scan.
---@param opts { root: string, out: string, max_files: integer, max_file_size: integer, max_cols?: integer }
---@return boolean ok, string? err
function M.run(opts)
	if not bigram.available() then
		return false, "no ffi/bit"
	end
	local files = list_files(opts.root, opts.max_files)
	if #files == 0 then
		return false, "no files"
	end
	local bg = bigram.new(opts.max_files, opts.max_cols)
	if not bg then
		return false, "bigram alloc failed"
	end
	for i, path in ipairs(files) do
		scan_file(bg, path, i - 1, opts.max_file_size)
	end
	return serialize.write({ root = opts.root, files = files, bigram = bg }, opts.out)
end

return M
