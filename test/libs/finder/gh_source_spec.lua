local F = require("test.libs.finder.helpers.finder")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- GitHub finder sources (gh_pr / gh_issue) and their row format: what the source feeds the pipeline
-- (items, message rows, count), dropping stale responses, the title following `repo:`, the pre-flight
-- toast, and how rows are drawn. The API module is faked in the child; nothing runs `gh`.

t.describe("finder gh source", function()
	t.before_each(function()
		F.setup()
		n.exec_lua(function()
			_G.toast_log = {}
			_G.Toast = function(msg, level)
				_G.toast_log[#_G.toast_log + 1] = { msg = msg, level = level }
			end
			-- Fake API: records searches and lets the test answer them in any order.
			_G.searches = {} ---@type { q: string, host: string, cb: fun(r: table), killed: boolean }[]
			_G.check_result = { repo = { host = "github.com", slug = "o/n" } }
			package.loaded["beast.libs.finder.source.gh.api"] = {
				check = function()
					return _G.check_result.repo, _G.check_result.err
				end,
				search = function(q, host, cb)
					local s = { q = q, host = host, cb = cb, killed = false }
					_G.searches[#_G.searches + 1] = s
					return {
						kill = function()
							s.killed = true
						end,
					}
				end,
			}
			local gh = require("beast.libs.finder.source.gh")
			_G.pr = gh.create("pr")
			_G.issue = gh.create("issue")

			_G.gh_item = function(num, extra)
				return vim.tbl_extend("force", {
					text = "#" .. num .. " t",
					kind = "pr",
					state = "open",
					number = num,
					title = "title " .. num,
					author = "dana",
					labels = {},
					url = "https://github.com/o/n/pull/" .. num,
				}, extra or {})
			end

			---Run source.get and collect what it emits; `answer` is delivered to the latest search.
			_G.run = function(source, pattern, answer)
				local items, finished = {}, false
				source.get({ pattern = pattern }, function(item)
					if item == nil then
						finished = true
					else
						items[#items + 1] = item
					end
				end)
				if answer then
					_G.searches[#_G.searches].cb(answer)
				end
				return items, finished
			end

			_G.texts = function(chunks)
				return table.concat(vim.tbl_map(function(c)
					return c.text
				end, chunks))
			end
		end)
	end)

	t.describe("source shape", function()
		t.it("has the default text of a pull request", function()
			t.eq(
				"is:pr state:open ",
				n.exec_lua(function()
					return _G.pr.initial_query
				end)
			)
		end)

		t.it("has the default text of an issue", function()
			t.eq(
				"is:issue state:open ",
				n.exec_lua(function()
					return _G.issue.initial_query
				end)
			)
		end)

		t.it("is live and async", function()
			t.eq(
				{ true, true },
				n.exec_lua(function()
					return { _G.pr.live, _G.pr.async }
				end)
			)
		end)

		t.it("keeps results while searching", function()
			t.eq(
				true,
				n.exec_lua(function()
					return _G.pr.retain_results
				end)
			)
		end)

		t.it("searches an empty prompt", function()
			t.eq(
				true,
				n.exec_lua(function()
					return _G.pr.run_when_empty
				end)
			)
		end)

		t.it("debounces to respect the search rate limit", function()
			t.eq(
				400,
				n.exec_lua(function()
					return _G.pr.debounce_ms
				end)
			)
		end)
	end)

	t.describe("check", function()
		t.it("fails without a repo", function()
			t.eq(
				false,
				n.exec_lua(function()
					_G.check_result = { repo = nil, err = "No GitHub remote found for this directory" }
					return _G.pr.check()
				end)
			)
		end)

		t.it("fails with a warning toast", function()
			local toast = n.exec_lua(function()
				_G.check_result = { repo = nil, err = "No GitHub remote found for this directory" }
				_G.pr.check()
				return _G.toast_log[1]
			end)
			t.eq("No GitHub remote found for this directory", toast.msg)
			t.eq(vim.log.levels.WARN, toast.level)
		end)

		t.it("passes with a repo", function()
			t.eq(
				true,
				n.exec_lua(function()
					return _G.pr.check()
				end)
			)
		end)

		t.it("titles with the kind and the repo", function()
			t.eq(
				"Pull Requests - o/n",
				n.exec_lua(function()
					_G.pr.check()
					return _G.pr.title()
				end)
			)
		end)

		t.it("titles an issue source", function()
			t.eq(
				"Issues - o/n",
				n.exec_lua(function()
					_G.issue.check()
					return _G.issue.title()
				end)
			)
		end)

		t.it("follows repo: in the prompt for the title", function()
			t.eq(
				"Pull Requests - neovim/neovim",
				n.exec_lua(function()
					_G.pr.check()
					return _G.pr.title({ pattern = "repo:neovim/neovim is:pr" })
				end)
			)
		end)
	end)

	t.describe("results", function()
		---Run the pull request source over `pattern` and answer it with `answer` (a builder name keeps
		---`gh_item` calls in the child).
		---@param pattern string
		---@param answer table
		---@param count integer how many `gh_item(k)` to put in `answer.items`, numbered `count` down to 1
		local function run(pattern, answer, count)
			return n.exec_lua(function(a)
				local items = {}
				for k = a.count, 1, -1 do
					items[#items + 1] = _G.gh_item(k)
				end
				a.answer.items = a.answer.items or items
				_G.pr.check()
				local got, finished = _G.run(_G.pr, a.pattern, a.answer)
				return {
					items = got,
					finished = finished,
					query = _G.searches[#_G.searches].q,
					host = _G.searches[#_G.searches].host,
					count = _G.pr.count(got, #got),
				}
			end, { pattern = pattern, answer = answer, count = count })
		end

		t.it("builds the query with the repo and the sort", function()
			t.eq("is:pr state:open repo:o/n sort:created-desc", run("is:pr state:open ", { total = 2 }, 2).query)
		end)

		t.it("passes the host through", function()
			t.eq("github.com", run("is:pr state:open ", { total = 2 }, 2).host)
		end)

		t.it("emits the items, numbered, and finishes", function()
			local r = run("is:pr state:open ", { total = 2 }, 2)
			t.eq(2, #r.items)
			t.eq(2, r.items[2].idx)
			t.eq(true, r.finished)
		end)

		t.it("counts matches over the total", function()
			t.eq("2/2", run("is:pr state:open ", { total = 2 }, 2).count)
		end)

		t.it("says more exist when capped", function()
			t.eq("1+", run("", { total = 250 }, 1).count)
		end)

		t.describe("an empty search", function()
			local r

			t.before_each(function()
				r = run("label:nope", { items = {}, total = 0 }, 0)
			end)

			t.it("gives one message row, flagged", function()
				t.eq(1, #r.items)
				t.eq(true, r.items[1].message)
				t.eq(true, r.items[1].is_error == nil)
			end)

			t.it("says what happened", function()
				t.eq("No results for this search", r.items[1].text)
			end)

			t.it("finishes", function()
				t.eq(true, r.finished)
			end)

			t.it("counts no message rows", function()
				t.eq("0/0", r.count)
			end)
		end)

		t.describe("an error", function()
			local r

			t.before_each(function()
				r = run("repo:x/y", { items = {}, error = { kind = "not_found", message = "repository not found or no access to it" } }, 0)
			end)

			t.it("gives two message rows", function()
				t.eq(2, #r.items)
			end)

			t.it("has a headline and a reason", function()
				t.eq("GitHub could not run this search:", r.items[1].text)
				t.eq("repository not found or no access to it", r.items[2].text)
			end)

			t.it("colours the rows as errors", function()
				t.eq(true, r.items[1].is_error and r.items[2].is_error)
			end)

			t.it("gives no count", function()
				t.eq("", r.count)
			end)
		end)
	end)

	t.describe("stale responses", function()
		---Start a search for "a", then one for "ab"; answer the first one late, then the second.
		---@return table
		local function race()
			return n.exec_lua(function()
				_G.pr.check()
				local first_items, first_finished = {}, false
				_G.pr.get({ pattern = "a" }, function(item)
					if item == nil then
						first_finished = true
					else
						first_items[#first_items + 1] = item
					end
				end)
				local first = _G.searches[#_G.searches]
				local second_items = _G.run(_G.pr, "ab")
				local killed = first.killed
				first.cb({ items = { _G.gh_item(9) }, total = 1 })
				local late = #first_items
				local finished = first_finished
				_G.searches[#_G.searches].cb({ items = { _G.gh_item(3) }, total = 1 })
				return { killed = killed, late = late, finished = finished, second = #second_items }
			end)
		end

		t.it("kills the previous process when a search starts", function()
			t.eq(true, race().killed)
		end)

		t.it("drops the late answer of the older search and never reports it finished", function()
			local r = race()
			t.eq(0, r.late)
			t.eq(false, r.finished)
		end)

		t.it("still delivers the newer answer", function()
			t.eq(1, race().second)
		end)

		t.it("kills the process on cancel and drops answers after it", function()
			local r = n.exec_lua(function()
				_G.pr.check()
				local got = {}
				_G.pr.get({ pattern = "c" }, function(item)
					if item then
						got[#got + 1] = item
					end
				end)
				local live = _G.searches[#_G.searches]
				_G.pr.cancel()
				local killed = live.killed
				live.cb({ items = { _G.gh_item(4) }, total = 1 })
				return { killed = killed, got = #got }
			end)
			t.eq(true, r.killed)
			t.eq(0, r.got)
		end)
	end)

	t.describe("row format", function()
		---`format.gh(gh_item(num, extra))` in the child: the drawn text, the hl of each chunk.
		---@param num integer
		---@param extra? table
		---@param drop? string a field of the item to remove
		---@return { text: string, hl: string[], first: string, icon: string }
		local function row(num, extra, drop)
			return n.exec_lua(function(a)
				local item = _G.gh_item(a.num, a.extra)
				if a.drop then
					item[a.drop] = nil
				end
				local chunks = require("beast.libs.finder.format").gh(item)
				return {
					text = _G.texts(chunks),
					hl = vim.tbl_map(function(c)
						return c.hl or "-"
					end, chunks),
					first = chunks[1].hl,
					icon = chunks[1].text,
				}
			end, { num = num, extra = extra, drop = drop })
		end

		t.it("has the number, the title, the author and the label", function()
			local r = row(30, { labels = { { name = "bug", color = "d73a4a" } } })
			t.eq(true, r.text:find("#30", 1, true) ~= nil)
			t.eq(true, r.text:find("title 30", 1, true) ~= nil)
			t.eq(true, r.text:find("@dana", 1, true) ~= nil)
			t.eq(true, r.text:find(" bug ", 1, true) ~= nil)
		end)

		t.it("colours the icon of an open pr", function()
			t.eq("BeastFinderGhOpen", row(30).first)
		end)

		for _, case in ipairs({
			{ "a draft pr", { state = "draft" }, "BeastFinderGhDraft" },
			{ "a merged pr", { state = "merged" }, "BeastFinderGhMerged" },
			{ "a closed pr", { state = "closed" }, "BeastFinderGhClosed" },
			{ "a closed issue (purple)", { kind = "issue", state = "closed" }, "BeastFinderGhMerged" },
			{ "a not planned issue (grey)", { kind = "issue", state = "not_planned" }, "BeastFinderGhDraft" },
		}) do
			t.it("colours the icon of " .. case[1], function()
				t.eq(case[3], row(1, case[2]).first)
			end)
		end

		t.it("draws issues and prs with different icons", function()
			t.eq(true, row(1).icon ~= row(1, { kind = "issue" }).icon)
		end)

		t.it("gives the label badge its own group", function()
			local r = row(30, { labels = { { name = "bug", color = "d73a4a" } } })
			t.eq(true, r.hl[#r.hl]:find("^BeastFinderGhLabel") ~= nil)
		end)

		t.it("draws no @ without an author", function()
			t.eq(true, row(1, nil, "author").text:find("@", 1, true) == nil)
		end)

		t.it("draws a message row dim", function()
			local r = n.exec_lua(function()
				local chunks = require("beast.libs.finder.format").gh({ message = true, text = "No results for this search" })
				return { text = _G.texts(chunks), hl = chunks[1].hl }
			end)
			t.eq("No results for this search", r.text)
			t.eq("BeastFinderGhMessage", r.hl)
		end)

		t.it("draws an error row in the error colour", function()
			t.eq(
				"BeastFinderGhError",
				n.exec_lua(function()
					return require("beast.libs.finder.format").gh({ message = true, is_error = true, text = "x" })[1].hl
				end)
			)
		end)
	end)
end)
