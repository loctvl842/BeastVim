local F = require("test.libs.finder.helpers.finder")
local gl = require("test.libs.finder.helpers.gl")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Covers docs/dev-specs/finder-gitlab-source.md Phase 3: what the sources feed the pipeline (items,
-- message rows, count), flag errors without a request, the unknown-user explanation, stale answers,
-- the title bar with the host and `project:`, and the pre-flight toast. vim.system is scripted.

local MR_LIST = gl.req("gitlab.com", "projects/o%2Fn/merge_requests")
local USERS = gl.req("gitlab.com", "users")

t.describe("finder gl source", function()
	t.before_each(function()
		F.setup()
		gl.install()
		n.exec_lua(function()
			_G.toasts = {}
			_G.Toast = function(msg, level)
				_G.toasts[#_G.toasts + 1] = { msg = msg, level = level }
			end
			local source_gl = require("beast.libs.finder.source.gl")
			_G.mr = source_gl.create("mr")
			_G.issue = source_gl.create("issue")
			---Run source.get and collect what it emits, once the answer arrived.
			_G.run = function(pattern)
				local items, finished = {}, false
				_G.mr.get({ pattern = pattern }, function(item)
					if item == nil then
						finished = true
					else
						items[#items + 1] = item
					end
				end)
				vim.wait(500, function()
					return finished
				end)
				return items, finished
			end
			---`run` reduced to plain data.
			_G.run_plain = function(pattern)
				local items, finished = _G.run(pattern)
				local out = {}
				for i, item in ipairs(items) do
					out[i] = {
						idx = item.idx,
						text = item.text,
						ref = item.ref,
						message = item.message == true,
						is_error = item.is_error == true,
					}
				end
				---@diagnostic disable-next-line: missing-parameter
				return { items = out, finished = finished, count = _G.mr.count(items) }
			end
		end)
	end)

	---@param pattern string
	---@return { items: table[], finished: boolean, count: string }
	local function run(pattern)
		return n.exec_lua(function(p)
			return _G.run_plain(p)
		end, pattern)
	end

	t.describe("source shape", function()
		t.it("defaults the text to state:opened for both sources", function()
			t.eq(
				{ "state:opened ", "state:opened " },
				n.exec_lua(function()
					return { _G.mr.initial_query, _G.issue.initial_query }
				end)
			)
		end)

		t.it("is live and async", function()
			t.eq(
				{ true, true },
				n.exec_lua(function()
					return { _G.mr.live == true, _G.mr.async == true }
				end)
			)
		end)

		t.it("keeps results while searching", function()
			t.eq(
				true,
				n.exec_lua(function()
					return _G.mr.retain_results == true
				end)
			)
		end)

		t.it("searches an empty prompt", function()
			t.eq(
				true,
				n.exec_lua(function()
					return _G.mr.run_when_empty == true
				end)
			)
		end)

		t.it("debounces by 400ms", function()
			t.eq(
				400,
				n.exec_lua(function()
					return _G.mr.debounce_ms
				end)
			)
		end)

		t.it("is registered as a source", function()
			t.eq(
				"gl_mr",
				n.exec_lua(function()
					return require("beast.libs.finder.source").gl_mr.name
				end)
			)
		end)
	end)

	t.describe("check and title", function()
		t.it("fails the check without a remote", function()
			gl.set({ ["git -C"] = gl.ok("") })
			t.eq(
				false,
				n.exec_lua(function()
					return _G.mr.check()
				end)
			)
		end)

		t.it("explains the failure with a warning toast", function()
			gl.set({ ["git -C"] = gl.ok("") })
			n.exec_lua(function()
				_G.mr.check()
			end)
			t.eq(
				{ msg = "No GitLab remote found for this directory", level = 3 },
				n.exec_lua(function()
					return _G.toasts[1]
				end)
			)
		end)

		t.it("passes the check on a gitlab.com remote", function()
			t.eq(
				true,
				n.exec_lua(function()
					return _G.mr.check()
				end)
			)
		end)

		t.it("titles gitlab.com without the host", function()
			t.eq(
				"Merge Requests - o/n",
				n.exec_lua(function()
					_G.mr.check()
					return _G.mr.title()
				end)
			)
		end)

		t.it("follows project: in the title", function()
			t.eq(
				"Merge Requests - a/b/c",
				n.exec_lua(function()
					_G.mr.check()
					return _G.mr.title({ pattern = "project:a/b/c" })
				end)
			)
		end)

		t.it("titles the issues source", function()
			t.eq(
				"Issues - o/n",
				n.exec_lua(function()
					_G.issue.check()
					return _G.issue.title()
				end)
			)
		end)

		t.it("names the host in the title on a self-hosted server", function()
			gl.install("git@gitlab.acme.dev:platform/payments/api.git")
			t.eq(
				"Merge Requests - gitlab.acme.dev/platform/payments/api",
				n.exec_lua(function()
					_G.mr.check()
					return _G.mr.title()
				end)
			)
		end)

		t.it("keeps the host for project: on a self-hosted server", function()
			gl.install("git@gitlab.acme.dev:platform/payments/api.git")
			t.eq(
				"Merge Requests - gitlab.acme.dev/x/y",
				n.exec_lua(function()
					_G.mr.check()
					return _G.mr.title({ pattern = "project:x/y" })
				end)
			)
		end)
	end)

	t.describe("results", function()
		t.before_each(function()
			n.exec_lua(function()
				_G.mr.check()
			end)
			gl.set({ [MR_LIST] = gl.http({ gl.mr(2, "Second"), gl.mr(1, "First") }, { ["X-Total"] = "2" }) })
		end)

		t.it("emits every item and finishes", function()
			local r = run("state:opened ")
			t.eq(2, #r.items)
			t.eq(true, r.finished)
		end)

		t.it("numbers the rows", function()
			t.eq(2, run("state:opened ").items[2].idx)
		end)

		t.it("counts matches over the total", function()
			t.eq("2/2", run("state:opened ").count)
		end)

		t.it("keeps the host's reference on the rows", function()
			t.eq("!2", run("state:opened ").items[1].ref)
		end)

		t.it("says more exist when the answer is capped", function()
			gl.set({ [MR_LIST] = gl.http({ gl.mr(1, "First") }, { ["X-Total"] = "250" }) })
			t.eq("1+", run("").count)
		end)

		t.describe("with no results", function()
			t.before_each(function()
				gl.set({ [MR_LIST] = gl.http({}) })
			end)

			t.it("gives one message row", function()
				t.eq(1, #run("label:nope").items)
			end)

			t.it("flags it as a message, not an error", function()
				local item = run("label:nope").items[1]
				t.eq({ true, false }, { item.message, item.is_error })
			end)

			t.it("words the message", function()
				t.eq("No results for this search", run("label:nope").items[1].text)
			end)

			t.it("counts nothing", function()
				t.eq(
					"0/0",
					n.exec_lua(function()
						---@diagnostic disable-next-line: missing-parameter
						return _G.mr.count({})
					end)
				)
			end)
		end)
	end)

	t.describe("mistakes in the text", function()
		local r, before

		t.before_each(function()
			n.exec_lua(function()
				_G.mr.check()
			end)
			before = #gl.calls()
			r = run("state:opened colour:red")
		end)

		t.it("make no request", function()
			t.eq(before, #gl.calls())
		end)

		t.it("give the message and the wrapped hint rows", function()
			t.eq(4, #r.items)
		end)

		t.it("name the unknown filter first", function()
			t.eq('Unknown filter "colour:".', r.items[1].text)
		end)

		t.it("mark every row as an error", function()
			t.eq(true, r.items[1].is_error and r.items[2].is_error and r.items[4].is_error)
		end)

		t.it("list the available flags", function()
			t.eq(true, r.items[2].text:find("Available: state, author", 1, true) ~= nil)
		end)

		t.it("show no count", function()
			t.eq("", r.count)
		end)
	end)

	t.describe("a failed search", function()
		local r

		t.before_each(function()
			n.exec_lua(function()
				_G.mr.check()
			end)
			gl.set({ [MR_LIST] = gl.http_error(404, "404 Project Not Found") })
			r = run("state:opened ")
		end)

		t.it("names the host in the heading", function()
			t.eq("GitLab could not run this search:", r.items[1].text)
		end)

		t.it("gives the reason", function()
			t.eq("project not found or no access to it", r.items[2].text)
		end)

		t.it("flags the rows as errors", function()
			t.eq(true, r.items[1].is_error and r.items[2].is_error)
		end)
	end)

	t.describe("an empty answer with a named user", function()
		t.before_each(function()
			n.exec_lua(function()
				_G.mr.check()
			end)
			gl.set({ [MR_LIST] = gl.http({}), [USERS] = gl.http({}) })
		end)

		t.it("explains the empty answer", function()
			local r = run("state:opened author:nobody-here")
			t.eq("GitLab could not run this search:", r.items[1].text)
			t.eq('user "nobody-here" was not found', r.items[2].text)
		end)

		t.it("shows no count", function()
			t.eq("", run("state:opened author:nobody-here").count)
		end)

		t.it("treats a real user with no match as just empty", function()
			gl.set({ [USERS] = gl.http({ { username = "dao" } }) })
			t.eq("No results for this search", run("state:opened author:dao").items[1].text)
		end)

		t.it("checks users only when the answer is empty", function()
			gl.set({ [MR_LIST] = gl.http({ gl.mr(1, "t") }) })
			run("author:dao")
			t.eq(0, gl.count(USERS))
		end)

		t.it("checks users only when the text names one", function()
			run("state:opened")
			t.eq(0, gl.count(USERS))
		end)
	end)

	t.describe("stale answers", function()
		t.it("are dropped", function()
			n.exec_lua(function()
				_G.mr.check()
			end)
			gl.set({ [MR_LIST] = gl.http({ gl.mr(1, "old") }) })
			gl.hold({ MR_LIST })
			n.exec_lua(function()
				_G.old_items, _G.new_items = {}, {}
				_G.mr.get({ pattern = "first" }, function(item)
					_G.old_items[#_G.old_items + 1] = item or "end"
				end)
			end)
			gl.hold({})
			gl.set({ [MR_LIST] = gl.http({ gl.mr(9, "new") }) })
			local r = n.exec_lua(function()
				_G.mr.get({ pattern = "second" }, function(item)
					_G.new_items[#_G.new_items + 1] = item or "end"
				end)
				vim.wait(500, function()
					return #_G.new_items > 0 and _G.new_items[#_G.new_items] == "end"
				end)
				_G.GH.release()
				vim.wait(100)
				local out = { old = #_G.old_items, new = _G.new_items[1] and _G.new_items[1].number }
				_G.mr.cancel()
				return out
			end)
			t.eq(0, r.old)
			t.eq(9, r.new)
		end)
	end)
end)
