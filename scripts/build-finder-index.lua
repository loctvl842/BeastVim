-- =========================================================================
-- Builder subprocess entry for the finder bigram index.
-- =========================================================================
-- Spawned by engine/index.lua as a headless child so the (potentially minutes-
-- long) content scan runs off the editor's main loop. Reads its parameters from
-- the environment (avoids argv-quoting pitfalls) and sets package.path itself —
-- the child runs with --clean, so it has no runtimepath. Builds via
-- engine/builder and exits:
--   0  = index written to $BEAST_FINDER_OUT
--   1  = missing params / build failed (caller falls back to a full scan)
--
--   nvim --headless --clean -l scripts/build-finder-index.lua
--
-- Env:
--   BEAST_FINDER_LUA_ROOT       abs path to the plugin's lua/ dir (package.path)
--   BEAST_FINDER_ROOT           repo root to index
--   BEAST_FINDER_OUT            output index file path
--   BEAST_FINDER_MAX_FILES      file cap
--   BEAST_FINDER_MAX_FILE_SIZE  per-file byte cap
--   BEAST_FINDER_MAX_COLS       optional bigram column cap
-- =========================================================================

local function fail(msg)
	io.stderr:write("build-finder-index: " .. msg .. "\n")
	vim.cmd("cquit 1")
end

local lua_root = os.getenv("BEAST_FINDER_LUA_ROOT")
local root = os.getenv("BEAST_FINDER_ROOT")
local out = os.getenv("BEAST_FINDER_OUT")
if not (lua_root and root and out) then
	return fail("missing BEAST_FINDER_LUA_ROOT/ROOT/OUT")
end

package.path = lua_root .. "/?.lua;" .. lua_root .. "/?/init.lua;" .. package.path

local ok, builder = pcall(require, "beast.libs.finder.source.live_grep.engine.builder")
if not ok then
	return fail("cannot load builder: " .. tostring(builder))
end

local built, err = builder.run({
	root = root,
	out = out,
	max_files = tonumber(os.getenv("BEAST_FINDER_MAX_FILES")) or 100000,
	max_file_size = tonumber(os.getenv("BEAST_FINDER_MAX_FILE_SIZE")) or (1024 * 1024),
	max_cols = tonumber(os.getenv("BEAST_FINDER_MAX_COLS")),
})
if not built then
	return fail(err or "build failed")
end

vim.cmd("qall!")
