local F = require("test.libs.finder.helpers.finder")
local gh = require("test.libs.finder.helpers.gh")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Pull requests -> commits (the chain through the real picker, gh scripted), and how commit rows are
-- drawn.

local SEARCH = "gh api -X GET search/issues"
local COMMITS = "gh api -X GET repos/o/n/commits/"

---@param number integer pull request
---@param p integer
---@return string
local function page(number, p)
	return ("gh api -X GET repos/o/n/pulls/%d/commits --hostname github.com -f per_page=100 -f page=%d"):format(number, p)
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

t.describe("finder gh commits", function()
	local commits, sha2

	t.before_each(function()
		F.setup()
		gh.install()
		commits = gh.commits(4)
		commits[2].commit.message = "Scoped grep\n\nonly the files you found"
		commits[2].commit.author.name = "Zed"
		commits[2].author = { login = "zed" }
		sha2 = commits[2].sha
		gh.set({
			[SEARCH] = gh.json({
				total_count = 2,
				items = {
					gh.pr(1, "Short title"),
					gh.pr(2, "Refactor the finder so that every picker can lead to the next one"),
				},
			}),
			[page(1, 1)] = gh.json(gh.reversed(commits)),
			[COMMITS .. commits[1].sha] = gh.json({ commit = { message = "m" }, files = gh.files(2, "lib/c") }),
			[COMMITS .. sha2] = gh.json({ commit = { message = "m" }, files = gh.files(1, "lib/z") }),
		})
		F.open("gh_pr")
		wait_row("Short title")
	end)

	t.after_each(F.close)

	t.it("offers both ways down in the hint", function()
		local hint = F.hint()
		t.eq(true, hint:find("<C-g> files changed in #1", 1, true) ~= nil)
		t.eq(true, hint:find("<C-t> commits in #1", 1, true) ~= nil)
	end)

	t.describe("commits of the first pull request", function()
		t.before_each(function()
			F.press("<C-t>")
			F.settle(400)
		end)

		t.it("titles with the pull request and the count", function()
			t.eq("PR Short title › Commits (4)", F.title())
			t.eq("4", F.count())
		end)

		t.it("lists newest first (the API answers oldest first), with the id and the subject", function()
			local rows = F.rows()
			t.eq(true, rows[1]:find("0000001", 1, true) ~= nil)
			t.eq(true, rows[1]:find("Commit 1 subject", 1, true) ~= nil)
			t.eq(true, rows[4]:find("Commit 4 subject", 1, true) ~= nil)
		end)

		t.it("puts the author and the age at the right edge of the row", function()
			local r = n.exec_lua(function()
				local parts = require("beast.libs.finder.format").gh_commit({
					short = "abc1234",
					subject = "Fix",
					author = "zed",
					date = "2026-11-01T10:00:00Z",
				})
				return {
					right = parts[#parts].right_align == true,
					author = parts[#parts].text:find("zed", 1, true) ~= nil,
				}
			end)
			t.eq({ right = true, author = true }, r)
		end)

		t.it("offers the way back in the hint", function()
			t.eq(true, F.hint():find("<BS> back to Pull Requests", 1, true) ~= nil)
		end)

		t.describe("preview", function()
			t.it("shows the first commit's diff", function()
				local text = F.preview_text()
				t.eq(true, text:find("lib/c1.lua", 1, true) ~= nil)
				t.eq(true, text:find("new 1", 1, true) ~= nil)
			end)

			t.it("gives the code no filetype of its own", function()
				t.eq(
					"",
					n.exec_lua(function()
						return vim.bo[FH.panes().preview.buf].filetype
					end)
				)
			end)

			t.it("gives each file a divider and the numbered diff below it", function()
				local text = F.preview_text()
				t.eq(true, text:find("━━ lib/c1.lua", 1, true) ~= nil)
				t.eq(true, text:find("▸ @@", 1, true) ~= nil)
			end)

			t.it("gives the added line its new number and a plus", function()
				t.eq(
					"    1 + ",
					n.exec_lua(function()
						local preview = FH.panes().preview
						local added
						for lnum, line in ipairs(vim.api.nvim_buf_get_lines(preview.buf, 0, -1, false)) do
							if line == "new 1" then
								added = lnum
							end
						end
						return vim.api.nvim_eval_statusline(vim.wo[preview.win].statuscolumn, { winid = preview.win, use_statuscol_lnum = added }).str
					end)
				)
			end)

			t.it("shows that commit's message and diff when moving", function()
				F.press("<C-j>")
				F.settle(300)
				local text = F.preview_text()
				t.eq(true, text:find("only the files you found", 1, true) ~= nil)
				t.eq(true, text:find("lib/z1.lua", 1, true) ~= nil)
			end)

			t.it("does not fetch a commit already seen again", function()
				F.press("<C-j>")
				F.settle(300)
				local fetched = gh.count(COMMITS)
				F.press("<C-k>")
				F.settle(300)
				F.press("<C-j>")
				F.settle(300)
				t.eq(fetched, gh.count(COMMITS))
			end)
		end)

		t.describe("typing", function()
			t.it("filters by subject", function()
				F.type("scoped")
				t.eq(true, F.has_row("Scoped grep"))
				t.eq(false, F.has_row("Commit 1 subject"))
			end)

			t.it("shows matches over total in the count", function()
				F.type("scoped")
				t.eq("1/4", F.count())
			end)

			t.it("filters by author", function()
				F.type("zed")
				t.eq(true, F.has_row("Scoped grep"))
			end)

			t.it("filters by id", function()
				F.type(string.sub(sha2, 1, 7))
				t.eq(true, F.has_row("Scoped grep"))
				t.eq(false, F.has_row("Commit 3 subject"))
			end)
		end)

		t.it("goes back to the pull requests without a new search", function()
			local searches = gh.count(SEARCH)
			F.type("")
			F.press("<BS>")
			F.settle(300)
			t.eq(true, F.has_row("Short title"))
			t.eq(searches, gh.count(SEARCH))
		end)

		t.describe("Enter", function()
			t.before_each(function()
				F.press("<CR>")
				F.settle(400)
			end)

			t.it("closes the picker", function()
				t.eq(0, F.window_count())
			end)

			t.it("opens a buffer with the message and the diff", function()
				local text = n.exec_lua(function()
					return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
				end)
				t.eq(true, text:find("Commit 1 subject", 1, true) ~= nil)
				t.eq(true, text:find("+new 1", 1, true) ~= nil)
			end)

			t.it("is a read-only diff named after the commit", function()
				local r = n.exec_lua(function()
					return { vim.bo.filetype, vim.bo.modifiable, vim.api.nvim_buf_get_name(0) }
				end)
				t.eq("diff", r[1])
				t.eq(false, r[2])
				t.eq(true, r[3]:find("o/n@0000001", 1, true) ~= nil)
			end)
		end)
	end)

	t.describe("errors and a cut list", function()
		---Move to the second pull request and open its commits.
		local function open_second()
			F.press("<C-j>")
			F.settle(200)
			F.press("<C-t>")
		end

		t.it("shows an error as a message row", function()
			gh.set({ [page(2, 1)] = gh.fail("gh: Not Found (HTTP 404)") })
			open_second()
			F.settle(400)
			t.eq(true, F.has_row("GitHub could not list the commits"))
		end)

		t.it("says so when the pull request has more commits than are listed", function()
			gh.set({
				[page(2, 1)] = gh.json(gh.commits(100, 1)),
				[page(2, 2)] = gh.json(gh.commits(100, 101)),
				[page(2, 3)] = gh.json(gh.commits(100, 201)),
				[page(2, 4)] = gh.json(gh.commits(1, 301)),
			})
			open_second()
			F.settle(800)
			t.eq(true, F.title():match("%(300, partial%)$") ~= nil)
		end)
	end)

	t.describe("rows leave room for the author at the right edge", function()
		local LONG = {
			short = "abcdef1",
			subject = ("long subject "):rep(8),
			author = "loctvl842",
			date = "2026-11-10T00:00:00Z",
		}

		---Run `format.<fn>(item, width)` in the child; returns the drawn columns (with the selection
		---prefix) and the text and source span of the given part. A table carries the args since
		---`width` can be nil.
		---@param fn string
		---@param item table
		---@param width? integer
		---@param part integer
		---@return table
		local function row(fn, item, width, part)
			return n.exec_lua(function(a)
				local parts = require("beast.libs.finder.format")[a.fn](a.item, a.width)
				local cols = 2
				for _, x in ipairs(parts) do
					cols = cols + vim.fn.strdisplaywidth(x.text)
				end
				return {
					cols = cols,
					text = parts[a.part].text,
					src_len = parts[a.part].src and (parts[a.part].src[2] - parts[a.part].src[1] + 1),
				}
			end, { fn = fn, item = item, width = width, part = part })
		end

		t.it("leaves a column before the author after a long subject", function()
			t.eq(true, row("gh_commit", LONG, 60, 3).cols + 1 <= 60)
		end)

		t.it("ends a cut subject in dots", function()
			t.eq("...", row("gh_commit", LONG, 60, 3).text:sub(-3))
		end)

		t.it("lets a match land only on the part still shown", function()
			local r = row("gh_commit", LONG, 60, 3)
			t.eq(#r.text - 3, r.src_len)
		end)

		t.it("keeps a short subject whole", function()
			t.eq("fix", row("gh_commit", vim.tbl_extend("force", LONG, { subject = "fix" }), 60, 3).text)
		end)

		t.it("cuts nothing without a width", function()
			t.eq(LONG.subject, row("gh_commit", LONG, nil, 3).text)
		end)

		t.it("leaves room on a branch row too", function()
			local branch = vim.tbl_extend("force", LONG, { name = "feature/a-long-branch-name", current = true })
			t.eq(true, row("git_branch", branch, 70, 4).cols + 1 <= 70)
		end)

		t.it("ends a cut branch subject in dots", function()
			local branch = vim.tbl_extend("force", LONG, { name = "feature/a-long-branch-name", current = true })
			t.eq("...", row("git_branch", branch, 70, 4).text:sub(-3))
		end)
	end)
end)
