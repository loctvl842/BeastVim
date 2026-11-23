local F = require("test.libs.finder.helpers.finder")
local gh = require("test.libs.finder.helpers.gh")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Issues -> grep in their title and description.

local SEARCH = "gh api -X GET search/issues"

---@param number integer
---@param title string
---@param body string
---@return table
local function issue(number, title, body)
	local raw = gh.pr(number, title)
	raw.pull_request = nil
	raw.html_url = "https://github.com/o/n/issues/" .. number
	raw.body = body
	return raw
end

---Wait until the list shows `needle`.
---@param needle string
local function wait_row(needle)
	n.exec_lua(function(s)
		FH.wait(function()
			return FH.has_row(s)
		end, 2000)
	end, needle)
end

t.describe("finder gh issue grep", function()
	t.before_each(function()
		F.setup()
		gh.install()
		gh.set({
			[SEARCH] = gh.json({
				total_count = 3,
				items = {
					issue(1, "Crash on startup", "It does crash\nwhen the Config is empty"),
					issue(2, "Slow list", "Nothing to see"),
					issue(3, "Config docs", "see the config page"),
				},
			}),
		})
		n.exec_lua(function()
			_G.opened = {}
			---@diagnostic disable-next-line: duplicate-set-field
			vim.ui.open = function(url)
				_G.opened[#_G.opened + 1] = url
				return {}, nil
			end
		end)
		F.open("gh_issue")
		wait_row("Crash on startup")
	end)

	t.after_each(F.close)

	t.it("lists the issues", function()
		t.eq(true, F.has_row("Crash on startup"))
	end)

	t.it("offers the grep in the hint", function()
		t.eq(true, F.hint():find("<C-g> grep 3 issues", 1, true) ~= nil)
	end)

	t.describe("drilled into the grep", function()
		t.before_each(function()
			F.press("<C-g>")
			F.settle(300)
		end)

		t.it("titles the grep", function()
			t.eq("3 Issues › Live Grep", F.title())
		end)

		t.it("shows a placeholder", function()
			t.eq(true, F.has_row("type to search the text of the 3 issues"))
		end)

		t.it("offers the way back", function()
			t.eq(true, F.hint():find("<BS> back to Issues", 1, true) ~= nil)
		end)

		t.it("headers a matching issue with its number and title", function()
			F.type("crash", 400)
			local first = F.rows()[1]
			t.eq(true, first:find("#1", 1, true) ~= nil and first:find("Crash on startup", 1, true) ~= nil)
		end)

		t.it("matches the title line and the body line (smart case)", function()
			F.type("crash", 400)
			t.eq(true, F.has_row("1:1"))
			t.eq(true, F.has_row("2:"))
			t.eq(true, F.has_row("It does crash"))
		end)

		t.it("drops an issue without the text", function()
			F.type("crash", 400)
			t.eq(false, F.has_row("Slow list"))
		end)

		t.it("is case-sensitive with a capital", function()
			F.type("Config", 400)
			t.eq(true, F.has_row("when the Config is empty"))
			t.eq(false, F.has_row("see the config page"))
		end)

		t.it("gives each issue its own header", function()
			F.type("Config", 400)
			t.eq(true, F.has_row("#1"))
			t.eq(true, F.has_row("#3"))
			t.eq(false, F.has_row("#2"))
		end)

		t.it("matches both with lower case", function()
			F.type("config", 400)
			t.eq(true, F.has_row("when the Config is empty"))
			t.eq(true, F.has_row("Config docs"))
		end)

		t.it("opens the issue in the browser on Enter and closes the picker", function()
			F.type("config", 400)
			F.press("<CR>")
			F.settle(300)
			t.eq(
				"https://github.com/o/n/issues/1",
				n.exec_lua(function()
					return _G.opened[1]
				end)
			)
			t.eq(0, F.window_count())
		end)

		t.it("goes back to the issue list without repeating the search", function()
			local searches = gh.count(SEARCH)
			F.type("")
			F.press("<BS>")
			F.settle(300)
			t.eq(true, F.has_row("Slow list"))
			t.eq(searches, gh.count(SEARCH))
		end)
	end)
end)
