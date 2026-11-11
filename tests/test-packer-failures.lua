-- =========================================================================
-- Test: beast.libs.packer.failures (persisted plugin install failures)
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-packer-failures.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local passed, failed = 0, 0

local function assert_eq(name, got, expected)
	if got == expected then
		passed = passed + 1
		io.write("  PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL: " .. name .. " — expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(got) .. "\n")
	end
end

-- Isolated state/data dirs so the test never touches the real ones.
local root = vim.fn.tempname()
vim.env.XDG_STATE_HOME = root .. "/state"
vim.env.XDG_DATA_HOME = root .. "/data"

local file = vim.fn.stdpath("state") .. "/beast/packer-failures.json"

--- Fresh module instance, as on a new nvim start.
local function fresh()
	package.loaded["beast.libs.packer.failures"] = nil
	return require("beast.libs.packer.failures")
end

local function write_raw(text)
	vim.fn.mkdir(vim.fn.fnamemodify(file, ":h"), "p")
	local f = assert(io.open(file, "w"))
	f:write(text)
	f:close()
end

io.write("\n--- record persists across restarts ---\n")
do
	local failures = fresh()
	failures.record("json", "https://github.com/x/json", "remote: Repository not found.")
	local again = fresh()
	local rec = again.list().json
	assert_eq("record survives reload", rec ~= nil, true)
	assert_eq("src kept", rec and rec.src, "https://github.com/x/json")
	assert_eq("reason kept", rec and rec.reason, "remote: Repository not found.")
	again.clear("json")
	assert_eq("clear persists", fresh().list().json, nil)
end

io.write("\n--- missing or corrupt file never breaks ---\n")
do
	vim.fn.delete(file)
	assert_eq("missing file is empty", next(fresh().list()), nil)
	write_raw("{not json")
	assert_eq("corrupt file is empty", next(fresh().list()), nil)
	write_raw('"just a string"')
	assert_eq("non-table json is empty", next(fresh().list()), nil)
	local failures = fresh()
	failures.record("a", "s", "r")
	assert_eq("recording after corrupt file works", fresh().list().a ~= nil, true)
	failures.clear("a")
end

io.write("\n--- retry window ---\n")
do
	local failures = fresh()
	failures.record("json", "s", "r")
	assert_eq("blocked inside window", failures.is_blocked("json", 24), true)
	assert_eq("not blocked with zero window", failures.is_blocked("json", 0), false)
	assert_eq("unknown plugin not blocked", failures.is_blocked("nope", 24), false)

	write_raw(vim.json.encode({ json = { src = "s", reason = "r", at = os.time() - 25 * 3600 } }))
	assert_eq("not blocked after window expires", fresh().is_blocked("json", 24), false)
	write_raw(vim.json.encode({ json = { src = "s", reason = "r", at = os.time() - 23 * 3600 } }))
	assert_eq("still blocked just inside window", fresh().is_blocked("json", 24), true)
	fresh().clear("json")
end

io.write("\n--- prune drops records that no longer apply ---\n")
do
	local failures = fresh()
	failures.record("removed", "s1", "r")
	failures.record("moved", "old-src", "r")
	failures.record("installed", "s3", "r")
	failures.record("kept", "s4", "r")
	vim.fn.mkdir(vim.fn.stdpath("data") .. "/site/pack/core/opt/installed", "p")

	failures.prune({
		{ name = "moved", src = "new-src" },
		{ name = "installed", src = "s3" },
		{ name = "kept", src = "s4" },
	})
	local list = fresh().list()
	assert_eq("removed from config is pruned", list.removed, nil)
	assert_eq("changed src is pruned", list.moved, nil)
	assert_eq("now-installed is pruned", list.installed, nil)
	assert_eq("still-failing record kept", list.kept ~= nil, true)
end

io.write("\n--- reason_for parses the combined vim.pack error ---\n")
do
	local failures = fresh()
	local err = table.concat({
		"vim.pack:",
		"",
		"`json`:",
		"/usr/share/nvim/runtime/lua/vim/pack.lua:251: remote: Repository not found.",
		"fatal: repository 'https://github.com/x/json/' not found",
		"",
		"`cpp`:",
		"/usr/share/nvim/runtime/lua/vim/pack.lua:251: Could not resolve host: github.com",
	}, "\n")
	assert_eq("first plugin reason", failures.reason_for(err, "json"), "remote: Repository not found.")
	assert_eq("second plugin reason", failures.reason_for(err, "cpp"), "Could not resolve host: github.com")
	assert_eq("unknown plugin falls back", failures.reason_for(err, "other"), "install failed")
	assert_eq("name with magic chars is literal", failures.reason_for(err, "j.on"), "install failed")
end

vim.fn.delete(root, "rf")
io.write(string.format("\n--- %d passed, %d failed ---\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
