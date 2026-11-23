local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Regression spec for the OSC52 provider's copy cache: Neovim calls paste() on
-- every read of "+" and overwrites the internal register with the result, so a
-- paste() that cannot answer (terminals refuse the OSC52 query) must serve the
-- last value this session copied. Otherwise `p` after y/d/x fails with E353.
t.describe("option OSC52 clipboard provider", function()
	t.before_each(function()
		h.clear()
		n.exec_lua(function()
			-- Force the SSH-without-display branch in option.lua wherever the test runs.
			vim.fn.setenv("SSH_TTY", "/dev/pts/9")
			vim.fn.setenv("DISPLAY", "")
			vim.fn.setenv("WAYLAND_DISPLAY", "")
			require("beast.option")
			_G.notify_count = 0
			local saved = vim.notify
			vim.notify = function(...)
				_G.notify_count = _G.notify_count + 1
				return saved(...)
			end
		end)
	end)

	t.it("installs over SSH without a display", function()
		t.eq("OSC 52", n.exec_lua("return vim.g.clipboard ~= nil and vim.g.clipboard.name"))
	end)

	t.describe("fresh session (nothing copied yet)", function()
		t.it("reads as an empty linewise register", function()
			t.eq({ "", "V" }, n.exec_lua("return { vim.fn.getreg('+'), vim.fn.getregtype('+') }"))
		end)

		t.it("warns about the terminal's native paste on each explicit read", function()
			-- Each explicit register read (getreg, getregtype) queries paste() once.
			t.eq(
				2,
				n.exec_lua(function()
					vim.fn.getreg("+")
					vim.fn.getregtype("+")
					return _G.notify_count
				end)
			)
		end)
	end)

	t.describe("copy/paste round-trip", function()
		---@param lines string[]
		---@param regtype string
		local function roundtrip(lines, regtype)
			return n.exec_lua(function(l, rt)
				vim.fn.setreg("+", l, rt)
				return { vim.fn.getreg("+"), vim.fn.getregtype("+") }
			end, lines, regtype)
		end

		t.it("charwise", function()
			t.eq({ "hello", "v" }, roundtrip({ "hello" }, "v"))
		end)

		t.it("linewise", function()
			t.eq({ "line one\nline two\n", "V" }, roundtrip({ "line one", "line two" }, "V"))
		end)

		t.it("blockwise", function()
			t.eq({ "ab\ncd", "\22" .. "2" }, roundtrip({ "ab", "cd" }, "b"))
		end)
	end)

	t.it("reads stay quiet once something has been copied", function()
		t.eq(
			0,
			n.exec_lua(function()
				vim.fn.setreg("+", { "quiet" }, "v")
				return _G.notify_count
			end)
		)
	end)
end)
