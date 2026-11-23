local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

---Run a clipboard op in the child, after optionally seeding the "+" register.
---@param op "read"|"write"|"toggle"|"clear"
---@param raw? string  raw register text to set before the op
---@param paths? string[]
---@param mode? string
---@return any
local function cb(op, raw, paths, mode)
	return n.exec_lua(function(o, r, p, m)
		local clipboard = require("beast.libs.explorer.clipboard")
		if r ~= false then
			vim.fn.setreg("+", r)
		end
		if o == "read" then
			return clipboard.read()
		elseif o == "write" then
			return clipboard.write(p, m)
		elseif o == "toggle" then
			return clipboard.toggle(p, m)
		end
		return clipboard.clear()
	end, op, raw or false, paths or {}, mode or "")
end

t.describe("explorer clipboard", function()
	t.before_each(function()
		h.clear()
		-- Replace the OS clipboard with an in-memory provider: tests must not read or clobber the real one.
		n.exec_lua(function()
			local store = {}
			local function copy(lines, regtype)
				store.v = { lines, regtype }
			end
			local function paste()
				return store.v or { {}, "v" }
			end
			vim.g.clipboard = {
				name = "beast-test-memory",
				copy = { ["+"] = copy, ["*"] = copy },
				paste = { ["+"] = paste, ["*"] = paste },
			}
		end)
	end)

	t.describe("read()", function()
		t.it("decodes an empty register to nil", function()
			t.eq(nil, cb("read", ""))
		end)

		t.it("rejects plain text with no mode line", function()
			t.eq(nil, cb("read", "hello world"))
		end)

		t.it("rejects paths with no trailing mode line", function()
			t.eq(nil, cb("read", "/tmp/a.txt\n/tmp/b.txt"))
		end)

		t.it("rejects a trailing line that is not copy/cut", function()
			t.eq(nil, cb("read", "/tmp/a.txt\nmaybe"))
		end)

		t.it("rejects a mode line with no paths above it", function()
			t.eq(nil, cb("read", "copy"))
		end)

		t.it("tolerates a trailing newline from the clipboard provider", function()
			t.eq({ paths = { "/tmp/a.txt" }, mode = "copy" }, cb("read", "/tmp/a.txt\ncopy\n"))
		end)
	end)

	t.describe("write()/read() round-trip", function()
		t.it("single path, copy", function()
			cb("write", nil, { "/tmp/a.txt" }, "copy")
			t.eq({ paths = { "/tmp/a.txt" }, mode = "copy" }, cb("read"))
		end)

		t.it("multiple paths, cut", function()
			cb("write", nil, { "/tmp/a.txt", "/tmp/b.txt", "/tmp/c.txt" }, "cut")
			t.eq({ paths = { "/tmp/a.txt", "/tmp/b.txt", "/tmp/c.txt" }, mode = "cut" }, cb("read"))
		end)

		t.it("a path literally named 'copy' still round-trips", function()
			cb("write", nil, { "/tmp/copy" }, "cut")
			t.eq({ paths = { "/tmp/copy" }, mode = "cut" }, cb("read"))
		end)
	end)

	t.describe("clear()", function()
		t.it("makes read() nil and blanks the raw register text", function()
			cb("write", nil, { "/tmp/a.txt" }, "copy")
			cb("clear")
			t.eq(nil, cb("read"))
			t.eq(
				"",
				n.exec_lua(function()
					return vim.fn.getreg("+")
				end)
			)
		end)
	end)

	t.describe("toggle()", function()
		t.it("on an empty clipboard marks it", function()
			cb("clear")
			t.eq({ paths = { "/tmp/a.txt" }, mode = "copy" }, cb("toggle", nil, { "/tmp/a.txt" }, "copy"))
			t.eq({ paths = { "/tmp/a.txt" }, mode = "copy" }, cb("read"))
		end)

		t.it("with the same mode clears it", function()
			cb("toggle", nil, { "/tmp/a.txt" }, "copy")
			t.eq(nil, cb("toggle", nil, { "/tmp/a.txt" }, "copy"))
			t.eq(nil, cb("read"))
		end)

		t.it("with a different mode overwrites instead of clearing", function()
			cb("write", nil, { "/tmp/a.txt" }, "copy")
			t.eq({ paths = { "/tmp/b.txt" }, mode = "cut" }, cb("toggle", nil, { "/tmp/b.txt" }, "cut"))
		end)
	end)

	t.describe("SSH-without-display OSC52 fallback", function()
		-- Mirrors the g:clipboard override in option.lua for SSH_TTY without a display: paste()
		-- always returns "" and warns, even for a value this same process just wrote. Querying it
		-- is pointless, so the local write is trusted and the provider's paste() must not run.
		---@return { read: table?, toggled: table?, toggled_is_nil: boolean, notify_count: integer }
		local function run()
			return n.exec_lua(function()
				local notify_count = 0
				local saved_notify = vim.notify
				vim.notify = function(...)
					notify_count = notify_count + 1
					return saved_notify(...)
				end
				vim.g.clipboard = {
					name = "OSC 52",
					copy = { ["+"] = function() end, ["*"] = function() end },
					paste = {
						["+"] = function()
							vim.notify("should not fire from clipboard.lua", vim.log.levels.WARN)
							return { "" }
						end,
						["*"] = function()
							return { "" }
						end,
					},
				}
				local clipboard = require("beast.libs.explorer.clipboard")
				clipboard.clear()
				clipboard.write({ "/tmp/a.txt" }, "copy")
				local read = clipboard.read()
				local toggled = clipboard.toggle({ "/tmp/a.txt" }, "copy")
				return { read = read, toggled_is_nil = toggled == nil, notify_count = notify_count }
			end)
		end

		t.it("read() falls back to the local write instead of the always-empty register", function()
			t.eq({ paths = { "/tmp/a.txt" }, mode = "copy" }, run().read)
		end)

		t.it("toggle-off still works (local fallback, not the register)", function()
			t.eq(true, run().toggled_is_nil)
		end)

		t.it("never calls the provider's paste() (no notify)", function()
			t.eq(0, run().notify_count)
		end)
	end)
end)
