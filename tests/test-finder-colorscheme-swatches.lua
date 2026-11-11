-- =========================================================================
-- Test: colorscheme swatch worker + cache (docs/dev-specs/finder-colorscheme-swatches.md, Phase 1)
--
-- Run as: nvim --clean --headless -l tests/test-finder-colorscheme-swatches.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local passed, failed = 0, 0

local function assert_test(name, cond, msg)
	if cond then
		passed = passed + 1
		io.write("  PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL: " .. name .. " - " .. (msg or "assertion failed") .. "\n")
	end
end

local function assert_eq(name, got, expected)
	assert_test(name, got == expected, "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(got))
end

-- Isolate the on-disk cache from the user's real one.
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
local real_stdpath = vim.fn.stdpath
vim.fn.stdpath = function(what)
	if what == "cache" then
		return tmp
	end
	return real_stdpath(what)
end

local swatches = require("beast.libs.finder.source.colorscheme_swatches")
local theme_file = vim.fn.getcwd() .. "/colors/monokai-pro.lua"

io.write("\n--- worker prints ten colors per theme ---\n")
do
	local worker = vim.fn.getcwd() .. "/lua/beast/libs/finder/source/colorscheme_swatches_worker.lua"
	local res = vim
		.system({ vim.v.progpath, "--headless", "-u", "NONE", "-l", worker, vim.o.runtimepath, "monokai-pro", "no-such-theme" }, { text = true })
		:wait()
	local out = vim.json.decode(res.stdout)
	assert_eq("exit code", res.code, 0)
	assert_eq("known theme has 10 entries", out["monokai-pro"] and #out["monokai-pro"], 10)
	assert_eq("background is Normal.bg", out["monokai-pro"][1], "#2d2a2e")
	assert_eq("foreground is Normal.fg", out["monokai-pro"][2], "#fcfcfa")
	assert_eq("unknown theme gets 10 entries", out["no-such-theme"] and #out["no-such-theme"], 10)
	assert_eq("unknown theme entries are false", out["no-such-theme"][1], false)
end

io.write("\n--- cache: miss, fill, hit, stale ---\n")
do
	assert_eq("cold cache misses", swatches.get("monokai-pro", theme_file), nil)

	local done = false
	swatches.ensure({ { name = "monokai-pro", path = theme_file } }, function()
		done = true
	end)
	vim.wait(10000, function()
		return done
	end, 20)
	assert_test("ensure completes", done)
	local colors = swatches.get("monokai-pro", theme_file)
	assert_eq("hit after ensure", colors and #colors, 10)
	assert_test("cache file written", vim.uv.fs_stat(tmp .. "/beast-finder-colorscheme-swatches.json") ~= nil)

	-- Warm cache: ensure must not spawn (on_done never fires).
	local fired = false
	swatches.ensure({ { name = "monokai-pro", path = theme_file } }, function()
		fired = true
	end)
	vim.wait(300, function()
		return fired
	end, 20)
	assert_eq("warm cache does not spawn", fired, false)

	-- A theme file with a different mtime is stale.
	local copy = tmp .. "/monokai-pro.lua"
	vim.fn.writefile(vim.fn.readfile(theme_file), copy)
	vim.uv.fs_utime(copy, 1000, 1000)
	assert_eq("changed mtime is a miss", swatches.get("monokai-pro", copy), nil)
end

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
