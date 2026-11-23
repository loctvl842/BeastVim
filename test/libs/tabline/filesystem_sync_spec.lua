local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Tabline filesystem sync (external delete/rename cleanup).
t.describe("tabline filesystem sync", function()
	t.before_each(function()
		h.clear()
		n.exec_lua(function()
			_G.buffers = require("beast.libs.tabline.buffers")
			_G.dir = (function()
				-- Real temp directory with resolved path (macOS /var -> /private/var).
				local d = vim.fn.tempname()
				vim.fn.mkdir(d, "p")
				return vim.uv.fs_realpath(d) or d
			end)()

			---Write a file named `name` with one line `text` into the temp dir; returns its path.
			_G.make_file = function(name, text)
				local path = _G.dir .. "/" .. name
				vim.fn.writefile({ text }, path)
				return path
			end
		end)
	end)

	t.after_each(function()
		n.exec_lua("vim.fn.delete(_G.dir, 'rf')")
	end)

	t.describe("find_fallback_buffer", function()
		t.before_each(function()
			n.exec_lua(function()
				_G.f1 = _G.make_file("fb1.txt", "1")
				_G.f2 = _G.make_file("fb2.txt", "2")
				vim.cmd.edit(_G.f1)
				vim.cmd.edit(_G.f2)
				_G.buf1 = vim.fn.bufnr(_G.f1)
				_G.buf2 = vim.fn.bufnr(_G.f2)
			end)
		end)

		t.it("prefers the alternate buffer", function()
			-- Current is f2, alternate should be f1.
			t.eq(true, n.exec_lua("return _G.buffers.find_fallback_buffer({ _G.buf2 }) == _G.buf1"))
		end)

		t.it("returns nil when all are excluded", function()
			t.eq(true, n.exec_lua("return _G.buffers.find_fallback_buffer({ _G.buf1, _G.buf2 }) == nil"))
		end)

		t.it("returns a valid listed buffer", function()
			t.eq(
				true,
				n.exec_lua(function()
					local any = _G.buffers.find_fallback_buffer({})
					return any ~= nil and vim.api.nvim_buf_is_valid(any)
				end)
			)
		end)
	end)

	t.describe("cleanup_stale", function()
		t.describe("inactive external delete", function()
			t.it("removes the stale buffer and keeps the others", function()
				t.eq(
					{ removed = true, gone = true, current_ok = true, others = true },
					n.exec_lua(function()
						local f1 = _G.make_file("a.txt", "a")
						local f2 = _G.make_file("b.txt", "b")
						local f3 = _G.make_file("c.txt", "c")
						vim.cmd.edit(f1)
						vim.cmd.edit(f2)
						vim.cmd.edit(f3)
						for _, f in ipairs({ f1, f2, f3 }) do
							_G.buffers.remember_file(vim.fn.bufnr(f))
						end
						os.remove(f1)
						local removed = _G.buffers.cleanup_stale()
						return {
							removed = removed == true,
							gone = vim.fn.bufnr(f1) == -1,
							current_ok = vim.api.nvim_buf_get_name(0) == f3,
							others = vim.fn.bufnr(f2) > 0 and vim.fn.bufnr(f3) > 0,
						}
					end)
				)
			end)
		end)

		t.describe("active external delete", function()
			t.it("switches to the surviving file", function()
				t.eq(
					{ removed = true, switched = true, gone = true, fallback = true },
					n.exec_lua(function()
						local f1 = _G.make_file("keep.txt", "keep")
						local f2 = _G.make_file("active.txt", "active")
						vim.cmd.edit(f1)
						vim.cmd.edit(f2)
						_G.buffers.remember_file(vim.fn.bufnr(f1))
						_G.buffers.remember_file(vim.fn.bufnr(f2))
						local before = vim.api.nvim_get_current_buf()
						os.remove(f2)
						local removed = _G.buffers.cleanup_stale()
						local after = vim.api.nvim_get_current_buf()
						return {
							removed = removed == true,
							switched = after ~= before,
							gone = vim.fn.bufnr(f2) == -1,
							fallback = vim.api.nvim_buf_get_name(after) == f1,
						}
					end)
				)
			end)

			t.it("opens a new empty buffer when there is no fallback", function()
				t.eq(
					{ removed = true, gone = true, empty = true },
					n.exec_lua(function()
						local f1 = _G.make_file("only.txt", "only")
						vim.cmd.edit(f1)
						_G.buffers.remember_file(vim.fn.bufnr(f1))
						os.remove(f1)
						local removed = _G.buffers.cleanup_stale()
						return {
							removed = removed == true,
							gone = vim.fn.bufnr(f1) == -1,
							empty = vim.api.nvim_buf_get_name(0) == "",
						}
					end)
				)
			end)
		end)

		t.describe("modified buffer safety", function()
			t.it("removes the unmodified stale buffer but keeps the modified one", function()
				t.eq(
					{ removed = true, clean_gone = true, dirty_remains = true, still_modified = true },
					n.exec_lua(function()
						local f1 = _G.make_file("dirty.txt", "dirty")
						local f2 = _G.make_file("clean.txt", "clean")
						vim.cmd.edit(f1)
						vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved" })
						vim.cmd.edit(f2)
						_G.buffers.remember_file(vim.fn.bufnr(f1))
						_G.buffers.remember_file(vim.fn.bufnr(f2))
						os.remove(f1)
						os.remove(f2)
						local removed = _G.buffers.cleanup_stale()
						return {
							removed = removed == true,
							clean_gone = vim.fn.bufnr(f2) == -1,
							dirty_remains = vim.fn.bufnr(f1) > 0,
							still_modified = vim.bo[vim.fn.bufnr(f1)].modified == true,
						}
					end)
				)
			end)
		end)

		t.describe("external rename", function()
			t.it("rewires an inactive buffer to the new path instead of closing it", function()
				t.eq(
					{ changed = true, rewired = true, old_gone = true, keep = true, current_keep = true },
					n.exec_lua(function()
						local old_path = _G.make_file("old.txt", "old")
						local keep = _G.make_file("keep.txt", "keep")
						local new_path = _G.dir .. "/new.txt"
						vim.cmd.edit(old_path)
						local old_buf = vim.fn.bufnr(old_path)
						_G.buffers.remember_file(old_buf)
						vim.cmd.edit(keep)
						_G.buffers.remember_file(vim.fn.bufnr(keep))
						os.rename(old_path, new_path)
						local changed = _G.buffers.cleanup_stale()
						return {
							changed = changed == true,
							rewired = vim.api.nvim_buf_is_valid(old_buf) and vim.api.nvim_buf_get_name(old_buf) == new_path,
							old_gone = vim.fn.bufnr(old_path) == -1,
							keep = vim.fn.bufnr(keep) > 0,
							current_keep = vim.api.nvim_buf_get_name(0) == keep,
						}
					end)
				)
			end)

			t.it("keeps focus and rewires the active buffer", function()
				t.eq(
					{ changed = true, same_buf = true, new_name = true, not_deleted = true },
					n.exec_lua(function()
						local old_path = _G.make_file("rename-me.txt", "x")
						local keep = _G.make_file("other.txt", "y")
						local new_path = _G.dir .. "/renamed.txt"
						vim.cmd.edit(keep)
						_G.buffers.remember_file(vim.fn.bufnr(keep))
						vim.cmd.edit(old_path)
						local old_buf = vim.fn.bufnr(old_path)
						_G.buffers.remember_file(old_buf)
						local before = vim.api.nvim_get_current_buf()
						os.rename(old_path, new_path)
						local changed = _G.buffers.cleanup_stale()
						local after = vim.api.nvim_get_current_buf()
						return {
							changed = changed == true,
							same_buf = after == before,
							new_name = vim.api.nvim_buf_get_name(after) == new_path,
							not_deleted = vim.api.nvim_buf_is_valid(old_buf) and old_buf == after,
						}
					end)
				)
			end)
		end)

		t.it("is a no-op when files exist", function()
			t.eq(
				{ removed = false, listed = true },
				n.exec_lua(function()
					local f1 = _G.make_file("exists.txt", "ok")
					vim.cmd.edit(f1)
					local removed = _G.buffers.cleanup_stale()
					return { removed = removed, listed = vim.fn.bufnr(f1) > 0 }
				end)
			)
		end)

		t.it("does not treat a buffer for a never-on-disk file as stale", function()
			t.eq(
				{ removed = false, survives = true, current_unchanged = true },
				n.exec_lua(function()
					local keep = _G.make_file("keep.txt", "keep")
					local fresh = _G.dir .. "/fresh.txt"
					vim.cmd.edit(keep)
					vim.cmd.edit(fresh)
					_G.buffers.remember_file(vim.fn.bufnr(keep))
					_G.buffers.remember_file(vim.fn.bufnr(fresh))
					local removed = _G.buffers.cleanup_stale()
					return {
						removed = removed,
						survives = vim.fn.bufnr(fresh) > 0 and vim.fn.buflisted(fresh) == 1,
						current_unchanged = vim.api.nvim_buf_get_name(0) == fresh,
					}
				end)
			)
		end)
	end)

	t.describe("autocmd wiring", function()
		---Set the tabline up, open `name`, delete it behind nvim's back, fire `event`, report removal.
		---@param event string
		local function removed_after(event)
			return n.exec_lua(function(ev)
				require("beast.libs.tabline").setup({})
				local path = _G.make_file("stale.txt", "x")
				vim.cmd.edit(path)
				os.remove(path)
				vim.cmd("doautocmd " .. ev)
				return vim.fn.bufnr(path) == -1
			end, event)
		end

		t.it("FocusGained removes a stale buffer", function()
			t.eq(true, removed_after("FocusGained"))
		end)

		t.it("ShellCmdPost removes a stale buffer", function()
			t.eq(true, removed_after("ShellCmdPost"))
		end)
	end)
end)
