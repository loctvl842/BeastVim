local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- beast.visibility: global hidden/gitignored state + change event.
t.describe("visibility", function()
	t.before_each(function()
		h.clear()
		n.exec_lua(function()
			_G.visibility = require("beast.visibility")
			_G.events = {}
			vim.api.nvim_create_autocmd("User", {
				pattern = "BeastVisibilityChanged",
				callback = function(ev)
					_G.events[#_G.events + 1] = ev.data
				end,
			})
		end)
	end)

	t.it("defaults hidden and gitignored to false", function()
		t.eq({ false, false }, n.exec_lua("return { _G.visibility.hidden, _G.visibility.gitignored }"))
	end)

	t.describe("toggle_hidden", function()
		t.it("flips hidden and fires the event with the post-toggle value", function()
			t.eq(
				{ hidden = true, gitignored = false, count = 1, key = "hidden", value = true },
				n.exec_lua(function()
					_G.visibility.toggle_hidden()
					return {
						hidden = _G.visibility.hidden,
						gitignored = _G.visibility.gitignored,
						count = #_G.events,
						key = _G.events[1] and _G.events[1].key,
						value = _G.events[1] and _G.events[1].value,
					}
				end)
			)
		end)

		t.it("flips back and fires a second event with false", function()
			t.eq(
				{ hidden = false, value = false },
				n.exec_lua(function()
					_G.visibility.toggle_hidden()
					_G.visibility.toggle_hidden()
					return { hidden = _G.visibility.hidden, value = _G.events[2] and _G.events[2].value }
				end)
			)
		end)
	end)

	t.describe("toggle_gitignored", function()
		t.it("flips gitignored independently and fires the event", function()
			t.eq(
				{ gitignored = true, hidden = false, key = "gitignored", value = true },
				n.exec_lua(function()
					_G.visibility.toggle_gitignored()
					return {
						gitignored = _G.visibility.gitignored,
						hidden = _G.visibility.hidden,
						key = _G.events[1] and _G.events[1].key,
						value = _G.events[1] and _G.events[1].value,
					}
				end)
			)
		end)

		t.it("flips back to false", function()
			t.eq(
				false,
				n.exec_lua(function()
					_G.visibility.toggle_gitignored()
					_G.visibility.toggle_gitignored()
					return _G.visibility.gitignored
				end)
			)
		end)
	end)

	t.describe("setup(opts)", function()
		t.it("merges initial overrides and leaves other keys at their default", function()
			t.eq(
				{ hidden = true, gitignored = false },
				n.exec_lua(function()
					_G.visibility.setup({ hidden = true })
					return { hidden = _G.visibility.hidden, gitignored = _G.visibility.gitignored }
				end)
			)
		end)

		t.it("resets to defaults when called with an empty table", function()
			t.eq(
				false,
				n.exec_lua(function()
					_G.visibility.setup({ hidden = true })
					_G.visibility.setup({})
					return _G.visibility.hidden
				end)
			)
		end)
	end)

	t.it("rejects direct assignment through the read-only proxy", function()
		t.eq(
			false,
			n.exec_lua(function()
				return (pcall(function()
					_G.visibility.hidden = true
				end))
			end)
		)
	end)
end)
