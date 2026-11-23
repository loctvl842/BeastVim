local F = require("test.libs.finder.helpers.finder")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Covers docs/dev-specs/finder-github-source.md Phase 2: `initial_query` fills the prompt (cursor at
-- its end) and is searched once on open, typing afterwards searches again, `title`/`debounce_ms`
-- override the defaults, and `check` can veto opening.

---Write `text` (after the prompt prefix) into the prompt and fire TextChanged, then wait.
---@param text string
local function change_prompt(text)
	n.exec_lua(function(text)
		local input = FH.panes().input
		local prefix = text and require("beast.libs.finder.config").prompt_prefix
		vim.api.nvim_buf_set_lines(input.buf, 0, 1, false, { prefix .. text })
		vim.api.nvim_exec_autocmds("TextChanged", { buffer = input.buf })
		FH.settle(200)
	end, text)
end

---@return string[]
local function searches()
	return n.exec_lua(function()
		return _G.searches
	end)
end

t.describe("finder initial query", function()
	t.before_each(function()
		F.setup()
		n.exec_lua(function()
			_G.searches, _G.checks, _G.check_ok = {}, 0, true
			FH.fake_source("fake_live", {
				live = true,
				async = true,
				initial_query = "is:fake ",
				run_when_empty = true,
				retain_results = true,
				debounce_ms = 20,
				title = function()
					return "Fake - o/n"
				end,
				check = function()
					_G.checks = _G.checks + 1
					return _G.check_ok
				end,
				get = function(filter, cb)
					_G.searches[#_G.searches + 1] = filter.pattern
					cb({ idx = 1, score = 1, text = "item for " .. filter.pattern })
					cb(nil)
				end,
				cancel = function() end,
			})
		end)
	end)

	t.after_each(F.close)

	t.describe("opening with a source that has an initial query", function()
		t.before_each(function()
			F.open("fake_live")
			F.settle(200)
		end)

		t.it("opens the prompt window", function()
			t.eq(
				true,
				n.exec_lua(function()
					return FH.panes().input ~= nil
				end)
			)
		end)

		t.it("fills the prompt with the initial query", function()
			t.eq("is:fake ", F.prompt())
		end)

		t.it("runs the check once", function()
			t.eq(
				1,
				n.exec_lua(function()
					return _G.checks
				end)
			)
		end)

		t.it("searches exactly once, with the initial query", function()
			t.eq({ "is:fake " }, searches())
		end)

		t.it("puts the cursor at the end of the prefilled text", function()
			-- `startinsert!` appends: the cursor sits just past the last character.
			t.eq(
				true,
				n.exec_lua(function()
					local input = FH.panes().input
					local line = vim.api.nvim_buf_get_lines(input.buf, 0, 1, false)[1]
					return vim.api.nvim_win_get_cursor(input.win)[2] == #line
				end)
			)
		end)

		t.it("takes the title from the source", function()
			t.eq(true, F.title():find("Fake - o/n", 1, true) ~= nil)
		end)

		-- The live child delivers the prompt's own change event for the initial text (the old headless run
		-- had to fire one by hand); the session must swallow it instead of searching again.
		t.it("does not search again on the echoed change event for the unchanged text", function()
			F.settle(300)
			t.eq(1, #searches())
		end)

		t.it("searches again with the typed text", function()
			change_prompt("is:fake hub")
			t.eq({ "is:fake ", "is:fake hub" }, searches())
		end)

		t.it("searches again when the initial text is retyped", function()
			change_prompt("is:fake hub")
			change_prompt("is:fake ")
			t.eq({ "is:fake ", "is:fake hub", "is:fake " }, searches())
		end)
	end)

	t.describe("when check vetoes opening", function()
		t.before_each(function()
			F.open("fake_live")
			F.close()
			n.exec_lua(function()
				_G.check_ok = false
			end)
			F.open("fake_live")
		end)

		t.it("runs the check again", function()
			t.eq(
				2,
				n.exec_lua(function()
					return _G.checks
				end)
			)
		end)

		t.it("opens no prompt window", function()
			t.eq(
				true,
				n.exec_lua(function()
					return FH.panes().input == nil
				end)
			)
		end)

		t.it("does not search", function()
			t.eq(1, #searches())
		end)
	end)
end)
