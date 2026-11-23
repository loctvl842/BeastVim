local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

t.describe("review session", function()
	t.before_each(function()
		h.clear()
		-- Test fixture in the child: `_G.fx` holds the helpers every case drives the lib with.
		n.exec_lua(function()
			local render = require("beast.libs.review.render")
			local review = require("beast.libs.review")
			local session = require("beast.libs.review.session")

			local fx = { notices = {}, dir = vim.fn.tempname(), counter = 0 }
			_G.fx = fx
			vim.fn.mkdir(fx.dir, "p")

			-- Capture notices (the lib reports through Toast, never vim.notify).
			require("beast.libs.toast").toast = function(msg, _, opts)
				fx.title = opts and opts.title
				fx.notices[#fx.notices + 1] = msg
			end
			vim.notify = function()
				error("review must not call vim.notify")
			end

			fx.review, fx.session = review, session

			---Write a fresh file and return its path.
			function fx.make_file(content)
				fx.counter = fx.counter + 1
				local path = fx.dir .. "/f" .. fx.counter .. ".txt"
				local f = assert(io.open(path, "wb"))
				f:write(content)
				f:close()
				return path
			end

			function fx.read(path)
				local f = io.open(path, "rb")
				if not f then
					return nil
				end
				local s = f:read("*a")
				f:close()
				return s
			end

			---Propose and return the buffer plus a table recording the callback result.
			function fx.propose(path, contents)
				local result = {}
				review.propose(path, contents, function(outcome, stats)
					result.outcome, result.stats = outcome, stats
				end)
				return vim.fn.bufnr(vim.fn.fnamemodify(path, ":p")), result
			end

			local actions = {
				accept = "accept",
				reject = "reject",
				accept_all = "accept_all",
				reject_all = "reject_all",
				next = "next_hunk",
				prev = "prev_hunk",
			}
			fx.actions = actions

			---Run a review action the way the global key does: against the current buffer.
			function fx.press(buf, action)
				vim.api.nvim_buf_call(buf, review[actions[action]])
			end

			function fx.marks(buf)
				return #vim.api.nvim_buf_get_extmarks(buf, render.namespace, 0, -1, {})
			end

			function fx.lines(buf)
				return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			end

			function fx.has_notice(text)
				return vim.iter(fx.notices):any(function(m)
					return m:find(text, 1, true) ~= nil
				end)
			end
		end)
	end)

	t.after_each(function()
		n.exec_lua(function()
			vim.fn.delete(_G.fx.dir, "rf")
		end)
	end)

	t.describe("accept all", function()
		t.it("keeps buffer and disk untouched while pending and paints bands", function()
			t.eq(
				{
					bands = true,
					buffer = { "a", "b", "c" },
					disk = "a\nb\nc\n",
					no_conflict_markers = true,
				},
				n.exec_lua(function()
					local fx = _G.fx
					local path = fx.make_file("a\nb\nc\n")
					local buf = fx.propose(path, "a\nX\nc\nd\n")
					return {
						bands = fx.marks(buf) > 0,
						buffer = fx.lines(buf),
						disk = fx.read(path),
						no_conflict_markers = not vim.tbl_contains(fx.lines(buf), "<<<<<<<"),
					}
				end)
			)
		end)

		t.it("saves the proposed content", function()
			t.eq(
				{
					outcome = "saved",
					accepted = 2,
					disk = "a\nX\nc\nd\n",
					marks = 0,
					released = true,
				},
				n.exec_lua(function()
					local fx = _G.fx
					local path = fx.make_file("a\nb\nc\n")
					local buf, res = fx.propose(path, "a\nX\nc\nd\n")
					fx.press(buf, "accept_all")
					return {
						outcome = res.outcome,
						accepted = res.stats.accepted,
						disk = fx.read(path),
						marks = fx.marks(buf),
						released = fx.session.get(buf) == nil,
					}
				end)
			)
		end)
	end)

	t.describe("reject all", function()
		t.it("leaves buffer and disk unchanged", function()
			t.eq(
				{ outcome = "rejected", rejected = 2, disk = "a\nb\nc\n", buffer = { "a", "b", "c" }, marks = 0 },
				n.exec_lua(function()
					local fx = _G.fx
					local path = fx.make_file("a\nb\nc\n")
					local buf, res = fx.propose(path, "a\nX\nc\nd\n")
					fx.press(buf, "reject_all")
					return {
						outcome = res.outcome,
						rejected = res.stats.rejected,
						disk = fx.read(path),
						buffer = fx.lines(buf),
						marks = fx.marks(buf),
					}
				end)
			)
		end)
	end)

	t.describe("hunk by hunk", function()
		t.it("handles line shifts and saves only the accepted hunks", function()
			-- Three hunks; the first accept adds lines, shifting the others down.
			t.eq(
				{
					cursor = 2,
					pending_after_one = true,
					pending_after_two = true,
					outcome = "saved",
					stats = { 2, 1 },
					disk = "1\nA\nB\nC\n3\n4\n5\n6\n7\n8\n9\nZ\n",
				},
				n.exec_lua(function()
					local fx = _G.fx
					local path = fx.make_file("1\n2\n3\n4\n5\n6\n7\n8\n9\n")
					local buf, res = fx.propose(path, "1\nA\nB\nC\n3\n4\n5\nX\n7\n8\n9\nZ\n")
					local out = { cursor = vim.api.nvim_win_get_cursor(0)[1] }
					fx.press(buf, "accept") -- 2 -> A B C
					out.pending_after_one = res.outcome == nil
					fx.press(buf, "reject") -- 6 -> X rejected
					out.pending_after_two = res.outcome == nil
					fx.press(buf, "accept") -- append Z
					out.outcome = res.outcome
					out.stats = { res.stats.accepted, res.stats.rejected }
					out.disk = fx.read(path)
					return out
				end)
			)
		end)

		t.it("reports rejected and writes nothing when every hunk is rejected one by one", function()
			t.eq(
				{ outcome = "rejected", disk = "a\nb\n" },
				n.exec_lua(function()
					local fx = _G.fx
					local path = fx.make_file("a\nb\n")
					local buf, res = fx.propose(path, "A\nB\n")
					fx.press(buf, "reject")
					return { outcome = res.outcome, disk = fx.read(path) }
				end)
			)
		end)
	end)

	t.describe("new file", function()
		t.it("shows no Current text and creates the file with exact content on accept", function()
			t.eq(
				{
					blank_before = { "" },
					outcome = "saved",
					disk = "x\ny\n",
					buffer_after = { "x", "y" },
				},
				n.exec_lua(function()
					local fx = _G.fx
					local path = fx.dir .. "/sub/new.txt"
					local buf, res = fx.propose(path, "x\ny\n")
					local out = { blank_before = fx.lines(buf) }
					fx.press(buf, "accept_all")
					out.outcome = res.outcome
					out.disk = fx.read(path)
					out.buffer_after = fx.lines(buf)
					return out
				end)
			)
		end)

		t.it("creates nothing when rejected", function()
			t.eq(
				{ outcome = "rejected", created = false, buffer = { "" } },
				n.exec_lua(function()
					local fx = _G.fx
					local path = fx.dir .. "/sub/never.txt"
					local buf, res = fx.propose(path, "x\n")
					fx.press(buf, "reject_all")
					return { outcome = res.outcome, created = fx.read(path) ~= nil, buffer = fx.lines(buf) }
				end)
			)
		end)
	end)

	t.describe("closing and cancelling", function()
		t.it("treats closing the buffer mid-review as reject all", function()
			t.eq(
				{ outcome = "rejected", disk = "a\nb\n" },
				n.exec_lua(function()
					local fx = _G.fx
					local path = fx.make_file("a\nb\n")
					local buf, res = fx.propose(path, "A\nb\n")
					vim.cmd("bwipeout! " .. buf)
					return { outcome = res.outcome, disk = fx.read(path) }
				end)
			)
		end)

		t.it("cancels when Claude gives up", function()
			t.eq(
				{ outcome = "cancelled", marks = 0, buffer = { "a", "b" }, disk = "a\nb\n" },
				n.exec_lua(function()
					local fx = _G.fx
					local path = fx.make_file("a\nb\n")
					local buf, res = fx.propose(path, "A\nb\n")
					fx.session.get(buf):cancel()
					return {
						outcome = res.outcome,
						marks = fx.marks(buf),
						buffer = fx.lines(buf),
						disk = fx.read(path),
					}
				end)
			)
		end)
	end)

	t.describe("queue", function()
		t.it("makes a second proposal wait its turn", function()
			t.eq(
				{
					second_waiting = true,
					first = "saved",
					second_started = true,
					second = "saved",
					disk = "A\nB\n",
				},
				n.exec_lua(function()
					local fx = _G.fx
					local path = fx.make_file("a\nb\n")
					local buf, res1 = fx.propose(path, "A\nb\n")
					local res2 = {}
					fx.review.propose(path, "A\nB\n", function(o)
						res2.outcome = o
					end)
					local out = { second_waiting = res2.outcome == nil and fx.session.get(buf) ~= nil }
					fx.press(buf, "accept_all")
					out.first = res1.outcome
					vim.wait(500, function()
						return fx.session.get(buf) ~= nil
					end)
					out.second_started = fx.session.get(buf) ~= nil
					fx.press(buf, "accept_all")
					out.second = res2.outcome
					out.disk = fx.read(path)
					return out
				end)
			)
		end)

		t.it("cancels queued requests through their handles without disturbing the active review", function()
			t.eq(
				{
					c = "cancelled",
					b = "cancelled",
					active_undisturbed = true,
					a = "cancelled",
					no_session_started = true,
					disk = "a\nb\n",
					callbacks = { a = 1, b = 1, c = 1 },
				},
				n.exec_lua(function()
					local fx = _G.fx
					local path = fx.make_file("a\nb\n")
					local res = { a = {}, b = {}, c = {} }
					local calls = { a = 0, b = 0, c = 0 }
					local function sub(key, text)
						return fx.review.propose(path, text, function(o)
							calls[key] = calls[key] + 1
							res[key].outcome = o
						end)
					end
					local cancel_a = sub("a", "A\nb\n")
					local buf = vim.fn.bufnr(vim.fn.fnamemodify(path, ":p"))
					local cancel_b = sub("b", "A\nB\n")
					local cancel_c = sub("c", "A\nb\nC\n")

					local out = {}
					cancel_c()
					out.c = res.c.outcome
					cancel_b()
					out.b = res.b.outcome
					out.active_undisturbed = fx.session.get(buf) ~= nil and res.a.outcome == nil

					cancel_c() -- already completed: no-op, no second callback
					cancel_a()
					out.a = res.a.outcome
					vim.wait(100)
					out.no_session_started = fx.session.get(buf) == nil
					out.disk = fx.read(path)
					cancel_a() -- after finish: no-op
					out.callbacks = calls
					return out
				end)
			)
		end)

		t.it("does not strand the rest when a proposal completes synchronously", function()
			t.eq(
				{ a = "saved", b = "saved", c_started = true, c = "saved", disk = "A\nB\n" },
				n.exec_lua(function()
					local fx = _G.fx
					local path = fx.make_file("a\nb\n")
					local buf, res_a = fx.propose(path, "A\nb\n")
					local res_b, res_c = {}, {}
					fx.review.propose(path, "A\nb\n", function(o)
						res_b.outcome = o -- identical to A's result: completes with no session
					end)
					fx.review.propose(path, "A\nB\n", function(o)
						res_c.outcome = o
					end)
					fx.press(buf, "accept_all")
					local out = { a = res_a.outcome }
					vim.wait(500, function()
						return fx.session.get(buf) ~= nil
					end)
					out.b = res_b.outcome
					out.c_started = fx.session.get(buf) ~= nil
					fx.press(buf, "accept_all")
					out.c = res_c.outcome
					out.disk = fx.read(path)
					return out
				end)
			)
		end)

		t.it("does not strand the queue when an on_done callback throws", function()
			t.eq(
				{ queued_started = true, failure_reported = true, queued = "saved" },
				n.exec_lua(function()
					local fx = _G.fx
					local path = fx.make_file("a\nb\n")
					local buf = vim.fn.bufnr(path, true)
					fx.review.propose(path, "A\nb\n", function()
						error("boom")
					end)
					local res2 = {}
					fx.review.propose(path, "A\nB\n", function(o)
						res2.outcome = o
					end)
					fx.press(buf, "accept_all")
					vim.wait(500, function()
						return fx.session.get(buf) ~= nil
					end)
					local out = {
						queued_started = fx.session.get(buf) ~= nil,
						failure_reported = fx.has_notice("on_done callback failed"),
					}
					fx.press(buf, "accept_all")
					out.queued = res2.outcome
					return out
				end)
			)
		end)

		t.it("resolves queued proposals when the buffer is closed", function()
			t.eq(
				{ pending = "rejected", queued = "rejected", disk = "a\nb\n" },
				n.exec_lua(function()
					local fx = _G.fx
					local path = fx.make_file("a\nb\n")
					local buf, res1 = fx.propose(path, "A\nb\n")
					local res2 = {}
					fx.review.propose(path, "A\nB\n", function(o)
						res2.outcome = o
					end)
					vim.cmd("bwipeout! " .. buf)
					vim.wait(500, function()
						return res2.outcome ~= nil
					end)
					return { pending = res1.outcome, queued = res2.outcome, disk = fx.read(path) }
				end)
			)
		end)
	end)

	t.describe("unsaved edits", function()
		t.it("are the Current side and get saved", function()
			t.eq(
				{
					before = { "a", "b", "mine" },
					outcome = "saved",
					user_edits = true,
					disk = "A\nb\nmine\n",
				},
				n.exec_lua(function()
					local fx = _G.fx
					local path = fx.make_file("a\nb\n")
					vim.fn.bufload(vim.fn.bufadd(path))
					local pre = vim.fn.bufnr(path)
					vim.api.nvim_buf_set_lines(pre, 2, 2, false, { "mine" })
					local out = { before = fx.lines(pre) }
					local buf, res = fx.propose(path, "A\nb\nmine\n")
					fx.press(buf, "accept_all")
					out.outcome = res.outcome
					out.user_edits = res.stats.user_edits
					out.disk = fx.read(path)
					return out
				end)
			)
		end)
	end)

	t.describe("identical proposal", function()
		t.it("is saved immediately with nothing accepted and no session", function()
			t.eq(
				{ outcome = "saved", accepted = 0, no_session = true },
				n.exec_lua(function()
					local fx = _G.fx
					local path = fx.make_file("a\nb\n")
					local buf, res = fx.propose(path, "a\nb\n")
					return {
						outcome = res.outcome,
						accepted = res.stats.accepted,
						no_session = fx.session.get(buf) == nil,
					}
				end)
			)
		end)
	end)

	t.describe("notices", function()
		t.it("go through Toast titled after the lib", function()
			t.eq(
				{ toasted = true, title = "review", outcome = "rejected" },
				n.exec_lua(function()
					local fx = _G.fx
					local path = fx.make_file("a\n")
					local buf, res = fx.propose(path, "A\n")
					local out = { toasted = #fx.notices > 0, title = fx.title }
					fx.press(buf, "reject_all")
					out.outcome = res.outcome
					return out
				end)
			)
		end)
	end)

	t.describe("actions with nothing pending", function()
		for _, name in ipairs({ "accept", "reject", "accept_all", "reject_all", "next", "prev" }) do
			t.it(name .. " says nothing is pending without erroring", function()
				t.eq(
					{ ok = true, notices = { "no review pending in this buffer" }, buffer = { "a" } },
					n.exec_lua(function(action)
						local fx = _G.fx
						local path = fx.make_file("a\n")
						vim.fn.bufload(vim.fn.bufadd(path))
						local buf = vim.fn.bufnr(path)
						fx.notices = {}
						local ok = pcall(vim.api.nvim_buf_call, buf, fx.review[fx.actions[action]])
						return { ok = ok, notices = fx.notices, buffer = fx.lines(buf) }
					end, name)
				)
			end)
		end
	end)

	t.describe("buffer scoping", function()
		t.it("only affects the current buffer's review", function()
			t.eq(
				{ b2 = "rejected", b1_pending = true, b1 = "saved" },
				n.exec_lua(function()
					local fx = _G.fx
					local p1, p2 = fx.make_file("1\n"), fx.make_file("2\n")
					local b1, r1 = fx.propose(p1, "one\n")
					local b2, r2 = fx.propose(p2, "two\n")
					fx.press(b2, "reject_all")
					local out = { b2 = r2.outcome, b1_pending = fx.session.get(b1) ~= nil and r1.outcome == nil }
					fx.press(b1, "accept_all")
					out.b1 = r1.outcome
					return out
				end)
			)
		end)
	end)

	t.describe("next / prev", function()
		t.it("wraps around the hunks", function()
			t.eq(
				{ start = 2, next = 5, next_wrap = 2, prev_wrap = 5, outcome = "rejected" },
				n.exec_lua(function()
					local fx = _G.fx
					local path = fx.make_file("1\n2\n3\n4\n5\n6\n7\n")
					local buf, res = fx.propose(path, "1\nA\n3\n4\nB\n6\n7\n")
					local function row()
						return vim.api.nvim_win_get_cursor(0)[1]
					end
					local out = { start = row() }
					fx.press(buf, "next")
					out.next = row()
					fx.press(buf, "next")
					out.next_wrap = row()
					fx.press(buf, "prev")
					out.prev_wrap = row()
					fx.press(buf, "reject_all")
					out.outcome = res.outcome
					return out
				end)
			)
		end)
	end)

	t.describe("hunk lines deleted by the user", function()
		t.it("makes accept skip instead of clobbering", function()
			t.eq(
				{ accepted = 0, outcome = "rejected", buffer = { "a", "c" }, told = true },
				n.exec_lua(function()
					local fx = _G.fx
					local path = fx.make_file("a\nb\nc\n")
					local buf, res = fx.propose(path, "a\nX\nc\n")
					vim.api.nvim_buf_set_lines(buf, 1, 2, false, {}) -- user removes the Current line
					fx.press(buf, "accept")
					return {
						accepted = res.stats.accepted,
						outcome = res.outcome,
						buffer = fx.lines(buf),
						told = fx.has_notice("moved out of reach"),
					}
				end)
			)
		end)
	end)

	t.describe("write failure", function()
		t.it("is reported as an error outcome with a message", function()
			t.eq(
				{ outcome = "error", has_message = true },
				n.exec_lua(function()
					local fx = _G.fx
					local path = fx.make_file("a\nb\n")
					local buf, res = fx.propose(path, "A\nb\n")
					vim.bo[buf].readonly = true
					fx.press(buf, "accept_all")
					local out = { outcome = res.outcome, has_message = type(res.stats.message) == "string" }
					vim.bo[buf].readonly = false
					return out
				end)
			)
		end)
	end)
end)
