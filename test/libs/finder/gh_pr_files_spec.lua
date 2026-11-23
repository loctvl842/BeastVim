local F = require("test.libs.finder.helpers.finder")
local gh = require("test.libs.finder.helpers.gh")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Pull requests -> files changed (the chain through the real picker, gh scripted).

local SEARCH = "gh api -X GET search/issues"
local LONG_TITLE = "Refactor the finder so that every picker can lead to the next one"

---@param number integer pull request
---@return string
local function page(number)
	return ("gh api -X GET repos/o/n/pulls/%d/files --hostname github.com -f per_page=100 -f page=1"):format(number)
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

---The preview's diff gutter text at `lnum`.
---@param lnum integer
---@return string
local function gutter(lnum)
	return n.exec_lua(function(l)
		local preview = FH.panes().preview
		return vim.api.nvim_eval_statusline(vim.wo[preview.win].statuscolumn, { winid = preview.win, use_statuscol_lnum = l }).str
	end, lnum)
end

---@return string[]
local function preview_lines()
	return n.exec_lua(function()
		return vim.api.nvim_buf_get_lines(FH.panes().preview.buf, 0, -1, false)
	end)
end

t.describe("finder gh pr files", function()
	t.before_each(function()
		F.setup()
		gh.install()
		local files2 = gh.files(2, "lib/mod")
		files2[2].patch = nil
		gh.set({
			[SEARCH] = gh.json({
				total_count = 2,
				items = { gh.pr(1, "Short title"), gh.pr(2, LONG_TITLE) },
			}),
			[page(1)] = gh.json(gh.files(3)),
			[page(2)] = gh.json(files2),
		})
		F.open("gh_pr")
		wait_row("Short title")
	end)

	t.after_each(F.close)

	t.it("lists the pull requests", function()
		t.eq(true, F.has_row("Short title"))
	end)

	t.it("names the first pull request in the hint", function()
		t.eq(true, F.hint():find("<C-g> files changed in #1", 1, true) ~= nil)
	end)

	t.describe("files of the first pull request", function()
		t.before_each(function()
			F.press("<C-g>")
			F.settle(400)
		end)

		t.it("titles with the pull request", function()
			t.eq("PR Short title › Files Changed (3)", F.title())
		end)

		t.it("lists only paths", function()
			t.eq(true, F.has_row("f1.lua"))
			t.eq(true, F.has_row("f3.lua"))
		end)

		t.it("counts the files", function()
			t.eq("3", F.count())
		end)

		t.it("offers the grep and the way back in the hint", function()
			t.eq(true, F.hint():find("<BS> back to Pull Requests", 1, true) ~= nil)
		end)

		t.it("previews the diff of the first file", function()
			local text = F.preview_text()
			t.eq(true, text:find("new 1", 1, true) ~= nil)
			t.eq(true, text:find("+new 1", 1, true) == nil)
		end)

		t.it("gives the code no filetype of its own", function()
			t.eq(
				"",
				n.exec_lua(function()
					return vim.bo[FH.panes().preview.buf].filetype
				end)
			)
		end)

		t.it("draws header, hunk band, removed, added", function()
			local lines = preview_lines()
			t.eq({ "modified  +1 -1", "▸ @@ -1 +1 @@", "old 1", "new 1" }, { lines[1]:match("^modified%s+%+1 %-1"), lines[2], lines[3], lines[4] })
		end)

		t.it("shows the old number and a minus on the removed line", function()
			t.eq(" 1    - ", gutter(3))
		end)

		t.it("shows the new number and a plus on the added line", function()
			t.eq("    1 + ", gutter(4))
		end)

		t.it("wraps long lines in the pane", function()
			t.eq(
				true,
				n.exec_lua(function()
					return vim.wo[FH.panes().preview.win].wrap
				end)
			)
		end)

		t.it("shows the next diff when moving", function()
			F.press("<C-j>")
			F.settle(300)
			t.eq(true, F.preview_text():find("new 2", 1, true) ~= nil)
		end)

		t.it("filters by path when typing", function()
			F.type("f3")
			t.eq(true, F.has_row("f3.lua"))
			t.eq(false, F.has_row("f1.lua"))
		end)

		t.it("shows matches over total in the count", function()
			F.type("f3")
			t.eq("1/3", F.count())
		end)

		t.describe("going back", function()
			local searches

			t.before_each(function()
				searches = gh.count(SEARCH)
				F.type("")
				F.press("<BS>")
				F.settle(300)
			end)

			t.it("returns to the pull requests", function()
				t.eq(true, F.title():match("^Pull Requests") ~= nil)
			end)

			t.it("leaves no diff gutter on the pull request preview", function()
				t.eq(
					{ "", "auto" },
					n.exec_lua(function()
						local win = FH.panes().preview.win
						return { vim.wo[win].statuscolumn, vim.wo[win].signcolumn }
					end)
				)
			end)

			t.it("makes no new search", function()
				t.eq(searches, gh.count(SEARCH))
			end)

			t.it("keeps the list", function()
				t.eq(true, F.has_row("Short title"))
			end)
		end)

		t.it("shows an Enter diff in a read-only scratch buffer named after the file", function()
			F.press("<BS>")
			F.settle(300)
			F.press("<C-j>")
			F.settle(300)
			F.press("<C-g>")
			F.settle(400)
			F.press("<C-j>")
			F.settle(300)
			F.press("<CR>")
			F.settle(300)
			t.eq(0, F.window_count())
			local buf = n.exec_lua(function()
				local b = vim.api.nvim_get_current_buf()
				return { vim.bo[b].filetype, vim.bo[b].modifiable, vim.api.nvim_buf_get_name(b) }
			end)
			t.eq("diff", buf[1])
			t.eq(false, buf[2])
			t.eq(true, buf[3]:find("o/n#2: lib/mod2.lua", 1, true) ~= nil)
		end)
	end)

	t.describe("files of the second pull request", function()
		t.before_each(function()
			F.press("<C-j>")
			F.settle(300)
			F.press("<C-g>")
			F.settle(400)
		end)

		t.it("trims a long title with ...", function()
			t.eq("PR Refactor the finder so that every pic... › Files Changed (2)", F.title())
		end)

		t.it("says so for a file with no patch", function()
			F.press("<C-j>")
			F.settle(300)
			t.eq(true, vim.tbl_contains(preview_lines(), "(diff too large or binary)"))
		end)
	end)

	t.describe("an error", function()
		t.before_each(function()
			gh.set({ [page(1)] = gh.fail("gh: Not Found (HTTP 404)") })
			F.close()
			F.open("gh_pr")
			wait_row("Short title")
			F.press("<C-g>")
			F.settle(400)
		end)

		t.it("is a message row", function()
			t.eq(true, F.has_row("GitHub could not list the files"))
		end)

		t.it("offers no chain from the message row", function()
			F.press("<C-g>")
			t.eq("Nothing to open from here", F.last_toast())
		end)
	end)
end)
