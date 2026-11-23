local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- beast.libs.finder.status: the pre-flight "checking" state and its change event.

---Run `fn` in the child, with `status` and an event recorder (`_G.fired`, the action seen at each firing).
local function child(fn, ...)
	return n.exec_lua(fn, ...)
end

t.describe("finder status", function()
	t.before_each(function()
		h.clear()
		child(function()
			_G.status = require("beast.libs.finder.status")
			_G.fired, _G.seen = 0, {}
			vim.api.nvim_create_autocmd("User", {
				pattern = "BeastFinderStatusChanged",
				callback = function()
					_G.fired = _G.fired + 1
					-- A plain counter counts firings: stop()'s event observes `nil`, which an array slot cannot hold.
					_G.seen[_G.fired] = _G.status.action or false
				end,
			})
		end)
	end)

	t.it("has no action by default", function()
		t.eq(
			true,
			child(function()
				return _G.status.action == nil
			end)
		)
	end)

	t.describe("start(label)", function()
		t.before_each(function()
			child(function()
				_G.status.start("Definition")
			end)
		end)

		t.it("sets the action", function()
			t.eq(
				"Definition",
				child(function()
					return _G.status.action
				end)
			)
		end)

		t.it("fires BeastFinderStatusChanged once", function()
			t.eq(
				1,
				child(function()
					return _G.fired
				end)
			)
		end)
	end)

	t.describe("start() again while active", function()
		t.before_each(function()
			child(function()
				_G.status.start("References")
				_G.first = _G.status.action
				_G.status.start("Declaration")
			end)
		end)

		t.it("applies the first label", function()
			t.eq(
				"References",
				child(function()
					return _G.first
				end)
			)
		end)

		t.it("overwrites it with the second label", function()
			t.eq(
				"Declaration",
				child(function()
					return _G.status.action
				end)
			)
		end)

		t.it("fires one event per start()", function()
			t.eq(
				2,
				child(function()
					return _G.fired
				end)
			)
		end)
	end)

	t.describe("stop()", function()
		t.before_each(function()
			child(function()
				_G.status.start("Implementation")
				_G.status.stop()
			end)
		end)

		t.it("clears the action", function()
			t.eq(
				true,
				child(function()
					return _G.status.action == nil
				end)
			)
		end)

		t.it("fires the event once more (start and stop)", function()
			t.eq(
				2,
				child(function()
					return _G.fired
				end)
			)
		end)

		t.it("lets start's event observe the action set", function()
			t.eq(
				"Implementation",
				child(function()
					return _G.seen[1]
				end)
			)
		end)

		t.it("lets stop's event observe the action already nil", function()
			t.eq(
				false,
				child(function()
					return _G.seen[2]
				end)
			)
		end)
	end)

	t.it("rejects direct assignment on the read-only proxy", function()
		t.eq(
			false,
			child(function()
				return (pcall(function()
					_G.status.action = "Definition"
				end))
			end)
		)
	end)
end)
