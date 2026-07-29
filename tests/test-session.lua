-- =========================================================================
-- Test: session lib — save guard, branch naming, load fallback, exists()
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-session.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Stub globals the explorer modules expect (see scripts/bench-explorer.lua)
-- since session.load() now reconstructs the explorer panel on restore.
_G.Theme = {
	get = function()
		return setmetatable({}, {
			__index = function()
				return "#ffffff"
			end,
		})
	end,
	refresh = function() end,
}

_G.Util = require("beast.util")

_G.Toast = function() end

package.loaded["nvim-web-devicons"] = {
	get_icon = function(_, _, _)
		return "󰈙", "DevIconDefault"
	end,
}

-- The real view lib (not bench-explorer.lua's simplified inline stub): this
-- test exercises real window-switching autocmds (explorer/autocmds.lua's
-- WinEnter handler), which needs the real View.win.is_normal()/find_normal().
_G.View = require("beast.libs.view")

local explorer = require("beast.libs.explorer")
local explorer_state = require("beast.libs.explorer.state")
local session = require("beast.libs.session")

-- =========================================================================
-- Test helpers
-- =========================================================================

local passed = 0
local failed = 0

local function assert_test(name, condition, msg)
	if condition then
		passed = passed + 1
		io.write("  PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL: " .. name .. " — " .. (msg or "assertion failed") .. "\n")
	end
end

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")

local sessions_dir = root .. "/sessions/"
local repo_dir = root .. "/repo"

--- Run a shell command in `dir`, asserting it succeeds.
local function sh(dir, cmd)
	local result = vim.system({ "sh", "-c", cmd }, { cwd = dir }):wait()
	assert(result.code == 0, "command failed: " .. cmd .. "\n" .. (result.stderr or ""))
end

--- Same encoding rule the lib uses internally, recomputed here so the test
--- can assert on exact file paths without reaching into private locals.
local function encode(s)
	return (s:gsub("[\\/:]+", "%%"))
end

local function wipe_buffers()
	vim.cmd("silent! %bwipeout!")
end

--- Fire the VimLeavePre autocmd session.setup() registered, synchronously.
local function trigger_save()
	vim.api.nvim_exec_autocmds("VimLeavePre", {})
end

--- Basenames of all currently open named buffers, sorted.
local function open_buffer_names()
	local names = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		local name = vim.api.nvim_buf_get_name(buf)
		if name ~= "" then
			names[#names + 1] = vim.fn.fnamemodify(name, ":t")
		end
	end
	table.sort(names)
	return names
end

vim.fn.mkdir(repo_dir, "p")
sh(repo_dir, "git init -q && git checkout -q -b main")
sh(repo_dir, "printf 'a' > a.lua && printf 'b' > b.lua && git add -A && git commit -q -m init")

vim.fn.chdir(repo_dir)
-- `getcwd()` resolves symlinks (e.g. macOS /tmp -> /private/tmp), so expected
-- paths must be built from it rather than from the pre-resolved `repo_dir`.
local repo_cwd = vim.fn.getcwd()
session.setup({ dir = sessions_dir })

-- =========================================================================
-- Save guard: no real file buffer open → no session file is written
-- =========================================================================

io.write("\n--- save guard (0 real buffers) ---\n")

wipe_buffers()
vim.cmd("enew") -- unnamed scratch buffer only
trigger_save()

local plain_path = sessions_dir .. encode(repo_cwd) .. ".vim"
assert_test("no session file written with 0 real buffers", vim.uv.fs_stat(plain_path) == nil, "found " .. plain_path)

-- =========================================================================
-- Save + exists() + load(): main branch (no suffix)
-- =========================================================================

io.write("\n--- save on main branch (no suffix) ---\n")

wipe_buffers()
vim.cmd("edit a.lua")
vim.cmd("split b.lua")
trigger_save()

assert_test("plain session file written on main", vim.uv.fs_stat(plain_path) ~= nil, "missing " .. plain_path)
assert_test("exists() true after save on main", session.exists() == true)

wipe_buffers()
session.load()
local names = open_buffer_names()
assert_test("load() on main restores a.lua + b.lua", names[1] == "a.lua" and names[2] == "b.lua" and #names == 2, vim.inspect(names))

-- =========================================================================
-- Feature branch: separate session file, main's is untouched
-- =========================================================================

io.write("\n--- feature branch gets its own session file ---\n")

local main_mtime = vim.uv.fs_stat(plain_path).mtime.sec
sh(repo_dir, "git checkout -q -b feature/login")

wipe_buffers()
vim.cmd("edit a.lua") -- reuse a real file so the buffer counts
trigger_save()

local branch_path = sessions_dir .. encode(repo_cwd) .. "%%" .. encode("feature/login") .. ".vim"
assert_test("branch-specific session file written", vim.uv.fs_stat(branch_path) ~= nil, "missing " .. branch_path)
assert_test("main's plain session file untouched by feature-branch save", vim.uv.fs_stat(plain_path).mtime.sec == main_mtime)

wipe_buffers()
session.load()
local branch_names = open_buffer_names()
assert_test("load() on feature branch restores only its own session", #branch_names == 1 and branch_names[1] == "a.lua", vim.inspect(branch_names))

-- =========================================================================
-- Brand-new branch with no session of its own → falls back to plain session
-- =========================================================================

io.write("\n--- new branch with no session falls back to plain ---\n")

sh(repo_dir, "git checkout -q -b feature/new-thing")

assert_test("exists() true via fallback on branch with no session of its own", session.exists() == true)

wipe_buffers()
session.load()
local fallback_names = open_buffer_names()
assert_test(
	"load() on branch with no session falls back to the plain (main) session",
	fallback_names[1] == "a.lua" and fallback_names[2] == "b.lua" and #fallback_names == 2,
	vim.inspect(fallback_names)
)

-- =========================================================================
-- Outside a git repo: no branch suffix, just the plain dir session
-- =========================================================================

io.write("\n--- non-git directory: plain session only, no %%branch suffix ---\n")

local plain_dir = root .. "/plain"
vim.fn.mkdir(plain_dir, "p")
sh(plain_dir, "printf 'c' > c.lua")
vim.fn.chdir(plain_dir)
local plain_cwd = vim.fn.getcwd()

wipe_buffers()
vim.cmd("edit c.lua")
trigger_save()

local plain_dir_path = sessions_dir .. encode(plain_cwd) .. ".vim"
assert_test("non-git dir gets a plain session file", vim.uv.fs_stat(plain_dir_path) ~= nil, "missing " .. plain_dir_path)

local suffixed = vim.fn.glob(sessions_dir .. encode(plain_cwd) .. "%%*.vim", true, true)
assert_test("non-git dir never gets a %%branch-suffixed file", #suffixed == 0, vim.inspect(suffixed))

wipe_buffers()
session.load()
assert_test("load() in a non-git dir restores c.lua", vim.deep_equal(open_buffer_names(), { "c.lua" }))

-- =========================================================================
-- Neither branch-specific nor plain session exists → no-op, no error
-- =========================================================================

io.write("\n--- no session anywhere → load()/exists() no-op ---\n")

local empty_repo = root .. "/empty-repo"
vim.fn.mkdir(empty_repo, "p")
sh(empty_repo, "git init -q && git checkout -q -b main")
vim.fn.chdir(empty_repo)

assert_test("exists() false when nothing was ever saved", session.exists() == false)

wipe_buffers()
local ok = pcall(session.load)
assert_test("load() does not error when nothing was ever saved", ok)
assert_test("load() is a true no-op (still just the unnamed buffer)", #vim.api.nvim_list_bufs() == 1)

-- =========================================================================
-- Explorer state: open + expanded folders + focus=explorer survives reload
-- =========================================================================

io.write("\n--- explorer state: open + expanded folders + focus=explorer ---\n")

local proj_a = root .. "/explorer-a"
vim.fn.mkdir(proj_a .. "/src/components", "p")
vim.fn.mkdir(proj_a .. "/tests", "p")
sh(proj_a, "git init -q && git checkout -q -b main")
vim.fn.writefile({ "return {}" }, proj_a .. "/src/components/button.lua")
sh(proj_a, "git add -A && git commit -q -m init")

vim.fn.chdir(proj_a)
local proj_a_cwd = vim.fn.getcwd()

explorer.close()
wipe_buffers()
vim.cmd("edit " .. vim.fn.fnameescape(proj_a_cwd .. "/src/components/button.lua"))
explorer.open(proj_a_cwd)
explorer_state.tree:open(proj_a_cwd .. "/src/components")
explorer_state.tree:open(proj_a_cwd .. "/tests")
trigger_save()

local sidecar_a = sessions_dir .. encode(proj_a_cwd) .. ".explorer.json"
assert_test("sidecar written when explorer was open at quit", vim.uv.fs_stat(sidecar_a) ~= nil, "missing " .. sidecar_a)

wipe_buffers()
session.load()

assert_test("explorer reopened at the saved root", explorer_state.tree and explorer_state.tree.root.path == proj_a_cwd)
assert_test(
	"folders expanded before quitting are expanded again (src)",
	explorer_state.tree.nodes[proj_a_cwd .. "/src"] and explorer_state.tree.nodes[proj_a_cwd .. "/src"].open == true
)
assert_test(
	"folders expanded before quitting are expanded again (tests)",
	explorer_state.tree.nodes[proj_a_cwd .. "/tests"] and explorer_state.tree.nodes[proj_a_cwd .. "/tests"].open == true
)
assert_test("focus restored to the explorer panel", explorer_state.view and vim.api.nvim_get_current_win() == explorer_state.view.win)

-- =========================================================================
-- Explorer state: same, but focus=main (cursor was in the last file)
-- =========================================================================

io.write("\n--- explorer state: open + expanded folders + focus=main ---\n")

local proj_b = root .. "/explorer-b"
vim.fn.mkdir(proj_b .. "/src", "p")
sh(proj_b, "git init -q && git checkout -q -b main")
vim.fn.writefile({ "return {}" }, proj_b .. "/src/main.lua")
sh(proj_b, "git add -A && git commit -q -m init")

vim.fn.chdir(proj_b)
local proj_b_cwd = vim.fn.getcwd()

explorer.close()
wipe_buffers()
vim.cmd("edit " .. vim.fn.fnameescape(proj_b_cwd .. "/src/main.lua"))
explorer.open(proj_b_cwd)
explorer_state.tree:open(proj_b_cwd .. "/src")
-- Move focus back to the file window before quitting, like a user who
-- browsed the explorer and then clicked back into their file.
vim.api.nvim_set_current_win(explorer_state.source_win)
trigger_save()

wipe_buffers()
session.load()

assert_test("explorer reopened at the saved root (focus=main case)", explorer_state.tree and explorer_state.tree.root.path == proj_b_cwd)
assert_test(
	"focus restored to the last edited file, not the explorer panel",
	explorer_state.view and vim.api.nvim_get_current_win() ~= explorer_state.view.win
)
assert_test("last edited file is the current buffer", vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t") == "main.lua")

-- =========================================================================
-- Explorer state: closed at quit stays closed (and clears a stale sidecar)
-- =========================================================================

io.write("\n--- explorer state: closed at quit stays closed ---\n")

local proj_c = root .. "/explorer-c"
vim.fn.mkdir(proj_c, "p")
sh(proj_c, "git init -q && git checkout -q -b main")
vim.fn.writefile({ "note" }, proj_c .. "/keep.lua")
sh(proj_c, "git add -A && git commit -q -m init")

vim.fn.chdir(proj_c)
local proj_c_cwd = vim.fn.getcwd()
local sidecar_c = sessions_dir .. encode(proj_c_cwd) .. ".explorer.json"

explorer.close()
wipe_buffers()
vim.cmd("edit keep.lua")
explorer.open(proj_c_cwd)
trigger_save()
assert_test("sidecar written while explorer was open", vim.uv.fs_stat(sidecar_c) ~= nil, "missing " .. sidecar_c)

-- explorer was already closed by the previous save(); a second save should
-- clear the now-stale sidecar rather than leave it pointing at open state.
trigger_save()
assert_test("stale sidecar cleared once explorer is closed at save time", vim.uv.fs_stat(sidecar_c) == nil, "sidecar still present")

wipe_buffers()
session.load()
assert_test("explorer stays closed on reload", not explorer_state.view or not explorer_state.view:is_valid())
assert_test("file buffers still restore normally", vim.deep_equal(open_buffer_names(), { "keep.lua" }))

-- =========================================================================
-- Explorer state: saved root deleted before reload fails silently
-- =========================================================================

io.write("\n--- explorer state: saved root deleted before reload ---\n")

local proj_d = root .. "/explorer-d"
vim.fn.mkdir(proj_d .. "/legacy", "p")
sh(proj_d, "git init -q && git checkout -q -b main")
vim.fn.writefile({ "note" }, proj_d .. "/keep.lua")
sh(proj_d, "git add -A && git commit -q -m init")

vim.fn.chdir(proj_d)
local proj_d_cwd = vim.fn.getcwd()
local legacy_root = proj_d_cwd .. "/legacy"

explorer.close()
wipe_buffers()
vim.cmd("edit keep.lua")
-- opts.restore=true here just forces the exact root for a deterministic
-- test setup; it is not simulating session restore itself.
explorer.open(legacy_root, { restore = true })
assert_test("explorer set up at the (soon to be deleted) sub-root", explorer_state.tree.root.path == legacy_root)
trigger_save()

local sidecar_d = sessions_dir .. encode(proj_d_cwd) .. ".explorer.json"
assert_test("sidecar written with the re-rooted explorer path", vim.uv.fs_stat(sidecar_d) ~= nil, "missing " .. sidecar_d)

vim.fn.delete(legacy_root, "rf")
wipe_buffers()

local ok_load = pcall(session.load)
assert_test("load() does not error when the saved explorer root is gone", ok_load)
assert_test("explorer stays closed when its saved root no longer exists", not explorer_state.view or not explorer_state.view:is_valid())
assert_test(
	"rest of the session (file buffers) restores normally despite the missing explorer root",
	vim.deep_equal(open_buffer_names(), { "keep.lua" })
)

-- =========================================================================
-- Summary
-- =========================================================================

vim.fn.delete(root, "rf")

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
if failed > 0 then
	os.exit(1)
else
	os.exit(0)
end
