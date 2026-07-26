-- =========================================================================
-- Test: Tabline filesystem sync (external delete/rename cleanup)
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-tabline-filesystem-sync.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

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
		io.write("  FAIL: " .. name .. " - " .. (msg or "assertion failed") .. "\n")
	end
end

--- Wipe all listed buffers so each case starts clean.
local function wipe_all()
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(b) then
			pcall(vim.api.nvim_buf_delete, b, { force = true })
		end
	end
end

--- Create a real temp directory with resolved path (macOS /var -> /private/var).
---@return string
local function make_temp_dir()
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p")
	return vim.uv.fs_realpath(dir) or dir
end

local buffers = require("beast.libs.tabline.buffers")

-- =========================================================================
-- Test: find_fallback_buffer
-- =========================================================================

io.write("\n--- find_fallback_buffer ---\n")

do
	wipe_all()
	local dir = make_temp_dir()
	local f1 = dir .. "/fb1.txt"
	local f2 = dir .. "/fb2.txt"
	vim.fn.writefile({ "1" }, f1)
	vim.fn.writefile({ "2" }, f2)

	vim.cmd.edit(f1)
	vim.cmd.edit(f2)
	local buf1 = vim.fn.bufnr(f1)
	local buf2 = vim.fn.bufnr(f2)

	-- Current is f2, alternate should be f1
	local fb = buffers.find_fallback_buffer({ buf2 })
	assert_test("prefers alternate buffer", fb == buf1, "got: " .. tostring(fb) .. " expected: " .. tostring(buf1))

	local none = buffers.find_fallback_buffer({ buf1, buf2 })
	assert_test("returns nil when all excluded", none == nil, "got: " .. tostring(none))

	local any = buffers.find_fallback_buffer({})
	assert_test("returns a valid listed buffer", any ~= nil and vim.api.nvim_buf_is_valid(any), "got: " .. tostring(any))
end

-- =========================================================================
-- Test: cleanup_stale — inactive external delete
-- =========================================================================

io.write("\n--- cleanup_stale: inactive external delete ---\n")

do
	wipe_all()
	local dir = make_temp_dir()
	local f1 = dir .. "/a.txt"
	local f2 = dir .. "/b.txt"
	local f3 = dir .. "/c.txt"
	vim.fn.writefile({ "a" }, f1)
	vim.fn.writefile({ "b" }, f2)
	vim.fn.writefile({ "c" }, f3)

	vim.cmd.edit(f1)
	vim.cmd.edit(f2)
	vim.cmd.edit(f3)

	os.remove(f1)
	local removed = buffers.cleanup_stale()
	assert_test("returns true when a buffer is removed", removed == true)
	assert_test("inactive stale buffer is gone", vim.fn.bufnr(f1) == -1)
	assert_test("current buffer stays on surviving file", vim.api.nvim_buf_get_name(0) == f3, "got: " .. vim.api.nvim_buf_get_name(0))
	assert_test("other buffers remain", vim.fn.bufnr(f2) > 0 and vim.fn.bufnr(f3) > 0)
end

-- =========================================================================
-- Test: cleanup_stale — active external delete
-- =========================================================================

io.write("\n--- cleanup_stale: active external delete ---\n")

do
	wipe_all()
	local dir = make_temp_dir()
	local f1 = dir .. "/keep.txt"
	local f2 = dir .. "/active.txt"
	vim.fn.writefile({ "keep" }, f1)
	vim.fn.writefile({ "active" }, f2)

	vim.cmd.edit(f1)
	vim.cmd.edit(f2)

	local before = vim.api.nvim_get_current_buf()
	os.remove(f2)
	local removed = buffers.cleanup_stale()
	local after = vim.api.nvim_get_current_buf()

	assert_test("returns true when current is removed", removed == true)
	assert_test("current buffer switches away", after ~= before)
	assert_test("stale current buffer is gone", vim.fn.bufnr(f2) == -1)
	assert_test("fallback is the surviving file", vim.api.nvim_buf_get_name(after) == f1, "got: " .. vim.api.nvim_buf_get_name(after))
end

-- =========================================================================
-- Test: cleanup_stale — active external delete with no fallback
-- =========================================================================

io.write("\n--- cleanup_stale: active delete, no fallback ---\n")

do
	wipe_all()
	local dir = make_temp_dir()
	local f1 = dir .. "/only.txt"
	vim.fn.writefile({ "only" }, f1)
	vim.cmd.edit(f1)

	os.remove(f1)
	local removed = buffers.cleanup_stale()
	assert_test("returns true when sole buffer is removed", removed == true)
	assert_test("stale sole buffer is gone", vim.fn.bufnr(f1) == -1)
	assert_test("a new empty buffer is current", vim.api.nvim_buf_get_name(0) == "", "got: " .. vim.api.nvim_buf_get_name(0))
end

-- =========================================================================
-- Test: cleanup_stale — modified buffer safety
-- =========================================================================

io.write("\n--- cleanup_stale: modified buffer safety ---\n")

do
	wipe_all()
	local dir = make_temp_dir()
	local f1 = dir .. "/dirty.txt"
	local f2 = dir .. "/clean.txt"
	vim.fn.writefile({ "dirty" }, f1)
	vim.fn.writefile({ "clean" }, f2)

	vim.cmd.edit(f1)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved" })
	vim.cmd.edit(f2)

	os.remove(f1)
	os.remove(f2)
	local removed = buffers.cleanup_stale()

	assert_test("removes unmodified stale buffer", removed == true)
	assert_test("unmodified stale buffer is gone", vim.fn.bufnr(f2) == -1)
	assert_test("modified stale buffer remains", vim.fn.bufnr(f1) > 0)
	assert_test("modified buffer still has unsaved flag", vim.bo[vim.fn.bufnr(f1)].modified == true)
end

-- =========================================================================
-- Test: cleanup_stale — external rename
-- =========================================================================

io.write("\n--- cleanup_stale: external rename ---\n")

do
	wipe_all()
	local dir = make_temp_dir()
	local old_path = dir .. "/old.txt"
	local new_path = dir .. "/new.txt"
	local keep = dir .. "/keep.txt"
	vim.fn.writefile({ "old" }, old_path)
	vim.fn.writefile({ "keep" }, keep)

	vim.cmd.edit(old_path)
	vim.cmd.edit(keep)

	os.rename(old_path, new_path)
	local removed = buffers.cleanup_stale()

	assert_test("returns true after rename of inactive file", removed == true)
	assert_test("old path buffer is gone", vim.fn.bufnr(old_path) == -1)
	assert_test("keep buffer remains", vim.fn.bufnr(keep) > 0)
	assert_test("current stays on keep", vim.api.nvim_buf_get_name(0) == keep, "got: " .. vim.api.nvim_buf_get_name(0))
end

-- =========================================================================
-- Test: cleanup_stale — active external rename
-- =========================================================================

io.write("\n--- cleanup_stale: active external rename ---\n")

do
	wipe_all()
	local dir = make_temp_dir()
	local old_path = dir .. "/rename-me.txt"
	local new_path = dir .. "/renamed.txt"
	local keep = dir .. "/other.txt"
	vim.fn.writefile({ "x" }, old_path)
	vim.fn.writefile({ "y" }, keep)

	vim.cmd.edit(keep)
	vim.cmd.edit(old_path)

	local before = vim.api.nvim_get_current_buf()
	os.rename(old_path, new_path)
	local removed = buffers.cleanup_stale()
	local after = vim.api.nvim_get_current_buf()

	assert_test("returns true after rename of active file", removed == true)
	assert_test("old path buffer is gone", vim.fn.bufnr(old_path) == -1)
	assert_test("current switches away", after ~= before)
	assert_test("fallback is keep buffer", vim.api.nvim_buf_get_name(after) == keep, "got: " .. vim.api.nvim_buf_get_name(after))
end

-- =========================================================================
-- Test: cleanup_stale — no-op when files exist
-- =========================================================================

io.write("\n--- cleanup_stale: no-op when files exist ---\n")

do
	wipe_all()
	local dir = make_temp_dir()
	local f1 = dir .. "/exists.txt"
	vim.fn.writefile({ "ok" }, f1)
	vim.cmd.edit(f1)

	local removed = buffers.cleanup_stale()
	assert_test("returns false when nothing is stale", removed == false)
	assert_test("buffer remains listed", vim.fn.bufnr(f1) > 0)
end

-- =========================================================================
-- Test: cleanup_stale via FocusGained / ShellCmdPost autocmds
-- =========================================================================

io.write("\n--- autocmd wiring: FocusGained / ShellCmdPost ---\n")

do
	wipe_all()

	_G.Theme = {
		get = function()
			return setmetatable({}, {
				__index = function()
					return "#ffffff"
				end,
			})
		end,
	}
	_G.Util = {
		colors = {
			set_hl = function() end,
			lighten = function()
				return "#ffffff"
			end,
			blend = function()
				return "#ffffff"
			end,
			inspect = function()
				return setmetatable({}, {
					__index = function()
						return nil
					end,
				})
			end,
		},
	}
	_G.Buffer = { delete = function() end }
	_G.View = { buf = { delete = function() end } }
	package.preload["beast"] = function()
		return { apply_highlights = function() end }
	end

	local tabline = require("beast.libs.tabline")
	tabline.setup({})

	local dir = make_temp_dir()
	local f_focus = dir .. "/focus.txt"
	local f_shell = dir .. "/shell.txt"
	vim.fn.writefile({ "focus" }, f_focus)
	vim.fn.writefile({ "shell" }, f_shell)

	vim.cmd.edit(f_focus)
	os.remove(f_focus)
	vim.cmd("doautocmd FocusGained")
	assert_test("FocusGained removes stale buffer", vim.fn.bufnr(f_focus) == -1)

	vim.cmd.edit(f_shell)
	os.remove(f_shell)
	vim.cmd("doautocmd ShellCmdPost")
	assert_test("ShellCmdPost removes stale buffer", vim.fn.bufnr(f_shell) == -1)
end

-- =========================================================================
-- Summary
-- =========================================================================

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
if failed > 0 then
	os.exit(1)
else
	os.exit(0)
end
