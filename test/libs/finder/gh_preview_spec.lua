local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- GitHub finder preview pane: what the pane shows (header at once, description and conversation when
-- fetched, PR-only fields only for PRs), relative times, caching, and dropping late answers for an
-- item the cursor already left. The detail fetch is faked in the child.

local NOW = 1794700800 -- 2026-11-15T00:00:00Z

---@param lines string[]
---@param needle string
---@return boolean
local function has(lines, needle)
	for _, l in ipairs(lines) do
		if l:find(needle, 1, true) then
			return true
		end
	end
	return false
end

---@param lines string[]
---@param needle string
---@return integer?
local function find(lines, needle)
	for i, l in ipairs(lines) do
		if l:find(needle, 1, true) then
			return i
		end
	end
end

---The line a `Label: value` field is drawn as (label column is 11 wide).
---@param label string
---@param value string
---@return string
local function f(label, value)
	return ("%-11s%s"):format(label .. ":", value)
end

---@class Beast.Test.PreviewBuild
---@field item? table fields merged over the default item
---@field drop? string[] item fields to remove
---@field detail? boolean|table `true`: the default detail, a table: merged over it
---@field drop_detail? string[] detail fields to remove
---@field raw_detail? table a detail used as given
---@field err? string

t.describe("finder gh preview", function()
	t.before_each(function()
		h.clear()
		n.exec_lua(function()
			_G.preview = require("beast.libs.finder.source.gh.preview")

			_G.item = function(extra)
				return vim.tbl_extend("force", {
					text = "#30 t",
					kind = "pr",
					state = "merged",
					number = 30,
					title = "feat(cli): function nodes",
					author = "loctvl842",
					labels = { { name = "bug", color = "d73a4a" }, { name = "cli", color = "ededed" } },
					url = "https://github.com/o/n/pull/30",
					repo = "o/n",
					host = "github.com",
					created = "2026-11-01T00:00:00Z",
					updated = "2026-11-14T00:00:00Z",
					comments = 2,
				}, extra or {})
			end

			_G.detail = function(extra)
				return vim.tbl_extend("force", {
					body = "## Summary\n\nA node written as a function.\n\nCloses #29",
					merged = "2026-11-02T00:00:00Z",
					closed = "2026-11-02T00:00:00Z",
					base = "main",
					head = "function-nodes",
					mergeable = "MERGEABLE",
					additions = 832,
					deletions = 37,
					files = 21,
					checks = { passed = 3, failed = 1, pending = 0 },
					conversation = {
						{ author = "dana", body = "Looks good", created = "2026-11-03T00:00:00Z", state = "APPROVED" },
						{ author = "sam", body = "Thanks!", created = "2026-11-04T00:00:00Z" },
					},
				}, extra or {})
			end
		end)
	end)

	---`preview.build` in the child.
	---@param spec Beast.Test.PreviewBuild
	---@return { lines: string[], span_count: integer, span1_hl: string }
	local function build(spec)
		return n.exec_lua(function(s, now)
			local item = _G.item(s.item)
			for _, key in ipairs(s.drop or {}) do
				item[key] = nil
			end
			local detail
			if s.raw_detail then
				detail = s.raw_detail
			elseif s.detail then
				detail = _G.detail(type(s.detail) == "table" and s.detail or nil)
				for _, key in ipairs(s.drop_detail or {}) do
					detail[key] = nil
				end
			end
			local lines, spans = _G.preview.build(item, detail, s.err, now)
			return { lines = lines, span_count = #spans, span1_hl = spans[1] and spans[1].hl }
		end, spec, NOW)
	end

	---@param spec Beast.Test.PreviewBuild
	---@return string[]
	local function lines_of(spec)
		return build(spec).lines
	end

	t.describe("reltime", function()
		for _, case in ipairs({
			{ "two weeks", "2026-11-01T00:00:00Z", "2 weeks ago" },
			{ "one day", "2026-11-14T00:00:00Z", "1 day ago" },
			{ "one hour", "2026-11-14T23:00:00Z", "1 hour ago" },
			{ "seconds", "2026-11-14T23:59:30Z", "just now" },
			{ "months", "2026-09-15T00:00:00Z", "2 months ago" },
			{ "years", "2024-11-15T00:00:00Z", "2 years ago" },
			{ "future clamps", "2027-01-01T00:00:00Z", "just now" },
			{ "garbage", "yesterday", "" },
			{ "fraction and Z", "2026-11-14T00:00:00.000Z", "1 day ago" },
			-- 2026-11-14T07:00:00+07:00 is 2026-11-14T00:00:00Z
			{ "positive offset", "2026-11-14T07:00:00.000+07:00", "1 day ago" },
			{ "negative offset", "2026-11-13T19:00:00-05:00", "1 day ago" },
		}) do
			t.it("reads " .. case[1], function()
				t.eq(
					case[3],
					n.exec_lua(function(ts, now)
						return require("beast.libs.finder.source.gh.preview").reltime(ts, now)
					end, case[2], NOW)
				)
			end)
		end

		t.it("reads nil as empty", function()
			t.eq(
				"",
				n.exec_lua(function(now)
					return require("beast.libs.finder.source.gh.preview").reltime(nil, now)
				end, NOW)
			)
		end)
	end)

	t.describe("build", function()
		t.describe("a GitLab item and detail", function()
			local lines

			t.before_each(function()
				lines = n.exec_lua(function(now)
					local gl_item = _G.item({
						provider = "gitlab",
						ref = "!412",
						number = 412,
						state = "open",
						repo = "platform/payments/api",
						host = "gitlab.acme.dev",
					})
					return (
						_G.preview.build(gl_item, {
							body = "Retry with backoff",
							base = "main",
							head = "retry-backoff",
							files = 6,
							pipeline = "passed",
							reviewers = { "mina", "lee" },
							assignees = { "dao" },
							milestone = "2026.4",
							conversation = {},
						}, nil, now)
					)
				end, NOW)
			end)

			t.it("uses the host's reference in the title", function()
				t.eq(true, has(lines, "feat(cli): function nodes  !412"))
			end)

			t.it("labels the project", function()
				t.eq(true, has(lines, f("Project", "platform/payments/api")))
				t.eq(false, has(lines, "Repo:"))
			end)

			t.it("lists reviewers, assignees, milestone and pipeline", function()
				t.eq(true, has(lines, f("Reviewers", "mina, lee")))
				t.eq(true, has(lines, f("Assignees", "dao")))
				t.eq(true, has(lines, f("Milestone", "2026.4")))
				t.eq(true, has(lines, f("Pipeline", "passed")))
			end)

			t.it("shows files without line totals", function()
				t.eq(true, has(lines, f("Changes", "6 files")))
			end)

			t.it("has no checks line without checks", function()
				t.eq(false, has(lines, "Checks:"))
			end)
		end)

		t.it("still writes #n for an item without a ref", function()
			t.eq(true, has(lines_of({}), "feat(cli): function nodes  #30"))
		end)

		t.describe("the header before the fetch answers", function()
			local r

			t.before_each(function()
				r = build({})
			end)

			t.it("puts the title and the number first", function()
				t.eq(true, r.lines[1]:find("feat(cli): function nodes", 1, true) ~= nil)
				t.eq(true, r.lines[1]:find("#30", 1, true) ~= nil)
			end)

			t.it("shows the status", function()
				t.eq(true, has(r.lines, "Status:") and has(r.lines, "Merged"))
			end)

			t.it("shows repo, author and labels", function()
				t.eq(true, has(r.lines, f("Repo", "o/n")))
				t.eq(true, has(r.lines, f("Author", "loctvl842")))
				t.eq(true, has(r.lines, f("Labels", "bug, cli")))
			end)

			t.it("shows relative dates", function()
				t.eq(true, has(r.lines, f("Created", "2 weeks ago")))
				t.eq(true, has(r.lines, f("Updated", "1 day ago")))
			end)

			t.it("shows a loading line", function()
				t.eq(true, has(r.lines, "Loading..."))
			end)

			t.it("makes PR-only fields wait for the fetch", function()
				t.eq(false, has(r.lines, "Checks:") or has(r.lines, "Changes:") or has(r.lines, "Mergeable:"))
			end)

			t.it("carries highlight spans", function()
				t.eq(true, r.span_count > 0)
				t.eq("BeastFinderPreviewTitle", r.span1_hl)
			end)

			t.it("precedes the rule with a blank line (never a markdown heading underline)", function()
				local rule = find(r.lines, "────")
				t.eq(true, rule ~= nil and r.lines[rule - 1] == "")
			end)
		end)

		t.describe("a PR with detail", function()
			local lines

			t.before_each(function()
				lines = lines_of({ detail = true })
			end)

			t.it("shows the branches in the status", function()
				t.eq(true, has(lines, "main <- function-nodes"))
			end)

			t.it("shows the merge time", function()
				t.eq(true, has(lines, f("Merged", "1 week ago")) or has(lines, f("Merged", "")))
			end)

			t.it("summarises the checks", function()
				t.eq(true, has(lines, f("Checks", "✓ 3  ✗ 1")))
			end)

			t.it("shows mergeable", function()
				t.eq(true, has(lines, f("Mergeable", "✓")))
			end)

			t.it("shows the changes", function()
				t.eq(true, has(lines, f("Changes", "21 files  +832 -37")))
			end)

			t.it("renders the description", function()
				t.eq(true, has(lines, "## Summary") and has(lines, "Closes #29"))
			end)

			t.it("has no loading line", function()
				t.eq(false, has(lines, "Loading..."))
			end)

			t.it("puts the conversation after the description", function()
				local conv = find(lines, "## Conversation")
				t.eq(true, conv ~= nil and conv > find(lines, "Closes #29"))
			end)

			t.it("orders the conversation oldest first", function()
				t.eq(true, find(lines, "@dana") < find(lines, "@sam"))
			end)

			t.it("shows the review verdict", function()
				t.eq(true, has(lines, "@dana  approved"))
			end)

			t.it("shows the comment text", function()
				t.eq(true, has(lines, "Looks good") and has(lines, "Thanks!"))
			end)
		end)

		t.it("shows conflicts", function()
			t.eq(true, has(lines_of({ detail = { mergeable = "CONFLICTING" } }), f("Mergeable", "✗ conflicts")))
		end)

		t.it("omits an unknown mergeable", function()
			t.eq(false, has(lines_of({ detail = { mergeable = "UNKNOWN" } }), "Mergeable:"))
		end)

		t.it("has no Checks line without checks", function()
			t.eq(false, has(lines_of({ detail = { checks = { passed = 0, failed = 0, pending = 0 } } }), "Checks:"))
		end)

		t.it("shows pending checks", function()
			t.eq(true, has(lines_of({ detail = { checks = { passed = 1, failed = 0, pending = 2 } } }), "✓ 1  ● 2"))
		end)

		t.it("says so for an empty description", function()
			t.eq(true, has(lines_of({ detail = { body = "", conversation = {} } }), "(no description)"))
		end)

		t.it("has no conversation heading without a conversation", function()
			t.eq(false, has(lines_of({ detail = { conversation = {} } }), "## Conversation"))
		end)

		t.it("replaces loading with the failure", function()
			t.eq(true, has(lines_of({ err = "boom" }), "Could not load details: boom"))
		end)

		t.describe("an issue", function()
			t.it("has a comments count", function()
				t.eq(true, has(lines_of({ item = { kind = "issue", state = "open", number = 41, title = "Hub crashes" } }), f("Comments", "2")))
			end)

			t.it("has no PR-only fields", function()
				local lines = lines_of({ item = { kind = "issue", state = "open", number = 41, title = "Hub crashes" } })
				t.eq(false, has(lines, "Checks:") or has(lines, "Changes:") or has(lines, "Mergeable:"))
			end)

			t.it("shows its status", function()
				t.eq(true, has(lines_of({ item = { kind = "issue", state = "open", number = 41 } }), "Open"))
			end)

			t.it("shows the close time when closed", function()
				t.eq(true, has(lines_of({ item = { kind = "issue", state = "closed" }, detail = true, drop_detail = { "merged" } }), "Closed:"))
			end)

			t.it("words not planned", function()
				t.eq(true, has(lines_of({ item = { kind = "issue", state = "not_planned" } }), "Closed (not planned)"))
			end)
		end)

		t.it("has no Labels line without labels", function()
			t.eq(false, has(lines_of({ item = { labels = {} } }), "Labels:"))
		end)

		t.it("has no Author line without an author", function()
			t.eq(false, has(lines_of({ drop = { "author" } }), "Author:"))
		end)
	end)

	t.describe("show", function()
		t.before_each(function()
			n.exec_lua(function()
				local api = require("beast.libs.finder.source.gh.api")
				_G.calls = {} ---@type { item: table, cb: fun(r: table), killed: boolean }[]
				---@diagnostic disable-next-line: duplicate-set-field
				api.detail = function(it, cb)
					local call = { item = it, cb = cb, killed = false }
					_G.calls[#_G.calls + 1] = call
					return {
						kill = function()
							call.killed = true
						end,
					}
				end

				local buf = vim.api.nvim_create_buf(false, true)
				local win = vim.api.nvim_open_win(buf, false, {
					relative = "editor",
					row = 0,
					col = 0,
					width = 70,
					height = 20,
					style = "minimal",
					border = "single",
				})
				_G.view = {
					buf = buf,
					win = win,
					is_valid = function()
						return vim.api.nvim_win_is_valid(win)
					end,
				}
				_G.text = function()
					return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
				end
				_G.a = _G.item()
				_G.b = _G.item({ number = 31, url = "https://github.com/o/n/pull/31", title = "second" })
				_G.show = function(it)
					_G.preview.show(_G.view, it)
				end
				---Deliver `res` to the fetch number `i` (an `extra` merges over the default detail).
				_G.answer = function(i, res)
					if res.detail then
						res.detail = _G.detail(res.detail)
					end
					_G.calls[i].cb(res)
				end
			end)
		end)

		---Run `fn` in the child (a thin wrapper: shows the intent at the call site).
		---@param fn fun(...): any
		---@param ... any
		---@return any
		local function child(fn, ...)
			return n.exec_lua(fn, ...)
		end

		t.it("draws the header at once", function()
			local r = child(function()
				_G.show(_G.a)
				return { _G.text():find("feat(cli): function nodes", 1, true) ~= nil, _G.text():find("Loading...", 1, true) ~= nil }
			end)
			t.eq({ true, true }, r)
		end)

		t.it("starts one fetch, for the shown item", function()
			local r = child(function()
				_G.show(_G.a)
				return { #_G.calls, _G.calls[1].item.number }
			end)
			t.eq({ 1, 30 }, r)
		end)

		t.it("uses markdown for the description", function()
			t.eq(
				"markdown",
				child(function()
					_G.show(_G.a)
					return vim.bo[_G.view.buf].filetype
				end)
			)
		end)

		t.it("names the PR in the title", function()
			t.eq(
				" PR #30 ",
				child(function()
					_G.show(_G.a)
					return vim.api.nvim_win_get_config(_G.view.win).title[1][1]
				end)
			)
		end)

		t.it("does not refetch when showing the same item again", function()
			t.eq(
				1,
				child(function()
					_G.show(_G.a)
					_G.show(_G.a)
					return #_G.calls
				end)
			)
		end)

		t.it("starts a second fetch when moving on, and kills the first", function()
			t.eq(
				{ 2, true },
				child(function()
					_G.show(_G.a)
					_G.show(_G.b)
					return { #_G.calls, _G.calls[1].killed }
				end)
			)
		end)

		t.it("drops a late answer for the old item", function()
			local r = child(function()
				_G.show(_G.a)
				_G.show(_G.b)
				_G.answer(1, { detail = {} })
				return { _G.text():find("A node written as a function", 1, true) == nil, _G.text():find("second", 1, true) ~= nil }
			end)
			t.eq({ true, true }, r)
		end)

		t.it("draws the current answer and drops Loading", function()
			local r = child(function()
				_G.show(_G.a)
				_G.show(_G.b)
				_G.answer(2, { detail = { body = "second body" } })
				return { _G.text():find("second body", 1, true) ~= nil, _G.text():find("Loading...", 1, true) == nil }
			end)
			t.eq({ true, true }, r)
		end)

		t.it("fetches a new item again and fills it in", function()
			local r = child(function()
				_G.show(_G.a)
				_G.show(_G.b)
				_G.answer(2, { detail = { body = "second body" } })
				_G.show(_G.a)
				local fetches = #_G.calls
				_G.answer(3, { detail = {} })
				return { fetches, _G.text():find("A node written as a function", 1, true) ~= nil }
			end)
			t.eq({ 3, true }, r)
		end)

		t.it("does not refetch a cached item and shows its detail instantly", function()
			local r = child(function()
				_G.show(_G.a)
				_G.show(_G.b)
				_G.answer(2, { detail = { body = "second body" } })
				_G.show(_G.a)
				_G.answer(3, { detail = {} })
				_G.show(_G.b)
				local after_b = #_G.calls
				local b_text = _G.text():find("second body", 1, true) ~= nil
				_G.show(_G.a)
				return { after_b, b_text, #_G.calls }
			end)
			t.eq({ 3, true, 3 }, r)
		end)

		t.it("explains a failed fetch", function()
			t.eq(
				true,
				child(function()
					local c = _G.item({ number = 32, url = "https://github.com/o/n/pull/32" })
					_G.show(c)
					_G.answer(1, { error = "HTTP 502" })
					return _G.text():find("Could not load details: HTTP 502", 1, true) ~= nil
				end)
			)
		end)

		t.describe("a killed fetch", function()
			local function setup_three()
				return child(function()
					local e = _G.item({ number = 40, url = "https://github.com/o/n/pull/40", title = "late" })
					local f2 = _G.item({ number = 41, url = "https://github.com/o/n/pull/41", title = "other" })
					_G.e = e
					_G.show(e)
					_G.show(f2)
					_G.show(e)
					return #_G.calls
				end)
			end

			t.it("starts three fetches", function()
				t.eq(3, setup_three())
			end)

			t.it("cannot answer for a later request", function()
				setup_three()
				local r = child(function()
					_G.answer(1, { error = "unexpected response from GitHub" })
					return { _G.text():find("Could not load details", 1, true) == nil, _G.text():find("Loading...", 1, true) ~= nil }
				end)
				t.eq({ true, true }, r)
			end)

			t.it("leaves the live fetch drawing", function()
				setup_three()
				t.eq(
					true,
					child(function()
						_G.answer(3, { detail = { body = "real body" } })
						return _G.text():find("real body", 1, true) ~= nil
					end)
				)
			end)
		end)

		t.describe("an empty list", function()
			t.it("clears the pane", function()
				t.eq(
					"",
					child(function()
						_G.show(_G.a)
						_G.show(nil)
						return _G.text()
					end)
				)
			end)

			t.it("forgets the item, so it redraws, from cache", function()
				local r = child(function()
					local e = _G.item({ number = 40, url = "https://github.com/o/n/pull/40", title = "late" })
					_G.show(e)
					_G.answer(1, { detail = { body = "real body" } })
					_G.show(nil)
					_G.show(e)
					return { _G.text():find("late", 1, true) ~= nil, _G.text():find("real body", 1, true) ~= nil }
				end)
				t.eq({ true, true }, r)
			end)
		end)

		t.describe("a message row", function()
			local r

			t.before_each(function()
				r = child(function()
					local d = _G.item({ number = 33, url = "https://github.com/o/n/pull/33" })
					_G.show(d)
					local pending = _G.calls[#_G.calls]
					_G.show({ message = true, text = "No results for this search" })
					local title = vim.api.nvim_win_get_config(_G.view.win).title
					return { text = _G.text(), killed = pending.killed, title = title and #title or 0 }
				end)
			end)

			t.it("clears the pane", function()
				t.eq("", r.text)
			end)

			t.it("kills the in-flight fetch", function()
				t.eq(true, r.killed)
			end)

			t.it("clears the title", function()
				t.eq(0, r.title)
			end)
		end)
	end)
end)
