local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- beast.libs.toast repeat merging ("xN" count).
t.describe("toast repeat merging", function()
	t.before_each(function()
		h.clear()
		n.exec_lua(function()
			local Record = require("beast.libs.toast.record")
			local State = require("beast.libs.toast.state")
			local stack = require("beast.libs.toast.stack")
			require("beast.libs.toast.config").setup({ stagger = 5, anim_ms = 10, timeout = 300 })

			-- The toast module owns its state privately; build a fresh one to inspect.
			_G.Record = Record
			_G.stack = stack
			_G.state = State()
			_G.push = function(msg, level, opts)
				stack.push(_G.state, Record(_G.state.next_id, msg, level, opts))
				_G.state.next_id = _G.state.next_id + 1
			end
			_G.settle = function(ms)
				vim.wait(ms or 80)
			end
			_G.body = function(view)
				return vim.api.nvim_buf_get_lines(view.buf, 0, -1, false)[1]
			end
		end)
	end)

	t.after_each(function()
		n.exec_lua(function()
			for _, v in ipairs(_G.state.views) do
				if v.timer then
					v.timer:stop()
				end
			end
			_G.stack.dismiss(_G.state)
			_G.settle(150)
		end)
	end)

	t.describe("count_label", function()
		---@param count integer
		local function label(count)
			return n.exec_lua(function(c)
				return _G.Record.count_label(c)
			end, count)
		end

		t.it("formats x2", function()
			t.eq("x2", label(2))
		end)

		t.it("formats x99", function()
			t.eq("x99", label(99))
		end)

		t.it("caps at x99+ from 100", function()
			t.eq("x99+", label(100))
		end)

		t.it("caps at x99+ far above", function()
			t.eq("x99+", label(5000))
		end)
	end)

	t.describe("merging", function()
		t.it("merges identical toasts into one view with a badge", function()
			t.eq(
				{ views = 1, count = 2, badge = true },
				n.exec_lua(function()
					_G.push("Pattern not found: foo", "WARN", { title = "Search" })
					_G.settle()
					_G.push("Pattern not found: foo", "WARN", { title = "Search" })
					_G.settle()
					return {
						views = #_G.state.views,
						count = _G.state.views[1].record.count,
						badge = _G.body(_G.state.views[1]):match("Pattern not found: foo x2") ~= nil,
					}
				end)
			)
		end)

		t.it("keeps climbing the count", function()
			t.eq(
				3,
				n.exec_lua(function()
					for _ = 1, 3 do
						_G.push("Pattern not found: foo", "WARN", { title = "Search" })
						_G.settle()
					end
					return _G.state.views[1].record.count
				end)
			)
		end)

		t.it("merges a repeat into the older matching toast across a different one", function()
			t.eq(
				{ views = 2, first = 4, other = 1 },
				n.exec_lua(function()
					for _ = 1, 3 do
						_G.push("Pattern not found: foo", "WARN", { title = "Search" })
						_G.settle()
					end
					_G.push("Other", "WARN", { title = "Search" })
					_G.settle()
					_G.push("Pattern not found: foo", "WARN", { title = "Search" })
					_G.settle()
					return {
						views = #_G.state.views,
						first = _G.state.views[1].record.count,
						other = _G.state.views[2].record.count,
					}
				end)
			)
		end)
	end)

	t.it("keeps toasts with a different title or level separate", function()
		t.eq(
			3,
			n.exec_lua(function()
				_G.push("Done", "INFO", { title = "Build" })
				_G.push("Done", "INFO", { title = "Test" })
				_G.push("Done", "WARN", { title = "Build" })
				_G.settle(120)
				return #_G.state.views
			end)
		)
	end)

	t.it("merges a burst inside the stagger window", function()
		t.eq(
			{ views = 1, count = 5 },
			n.exec_lua(function()
				for _ = 1, 5 do
					_G.push("burst", "INFO")
				end
				_G.settle(120)
				return { views = #_G.state.views, count = _G.state.views[1].record.count }
			end)
		)
	end)

	t.it("never merges sticky, segment and merge=false toasts", function()
		t.eq(
			6,
			n.exec_lua(function()
				_G.push("sticky", "INFO", { timeout = false })
				_G.push("sticky", "INFO", { timeout = false })
				_G.push("segments", "INFO", { segments = { { text = "segments" } } })
				_G.push("segments", "INFO", { segments = { { text = "segments" } } })
				_G.push("no merge", "INFO", { merge = false })
				_G.push("no merge", "INFO", { merge = false })
				_G.settle(200)
				return #_G.state.views
			end)
		)
	end)

	t.describe("timer restart", function()
		t.it("stays visible after the original timeout, then goes after the restarted window", function()
			t.eq(
				{ still_visible = 1, gone = 0 },
				n.exec_lua(function()
					_G.push("keepalive", "INFO") -- 300 ms timeout
					_G.settle(30)
					vim.wait(200)
					_G.push("keepalive", "INFO") -- repeat at ~230 ms: the original would die at 300 ms
					vim.wait(200) -- ~430 ms since first show, ~200 ms since repeat
					local still_visible = #_G.state.views
					vim.wait(300)
					return { still_visible = still_visible, gone = #_G.state.views }
				end)
			)
		end)
	end)

	t.it("starts a new toast at count 1 after dismissal", function()
		t.eq(
			{ dismissed = 0, count = 1 },
			n.exec_lua(function()
				_G.push("again", "INFO")
				_G.push("again", "INFO")
				vim.wait(600)
				local dismissed = #_G.state.views
				_G.push("again", "INFO")
				_G.settle()
				return { dismissed = dismissed, count = _G.state.views[1] and _G.state.views[1].record.count }
			end)
		)
	end)

	t.it("opens a new toast for a repeat during fade-out", function()
		t.eq(
			{ closing = true, open = 1 },
			n.exec_lua(function()
				_G.push("fading", "INFO")
				_G.settle()
				local first = _G.state.views[1]
				_G.stack.remove(_G.state, first.record.id)
				local closing = first.closing
				_G.push("fading", "INFO")
				_G.settle(120)
				local open = 0
				for _, v in ipairs(_G.state.views) do
					if not v.closing then
						open = open + 1
					end
				end
				return { closing = closing, open = open }
			end)
		)
	end)

	t.it("grows the width with the badge", function()
		t.eq(
			4, -- x14 adds 4 columns (space + 3 chars)
			n.exec_lua(function()
				local one = _G.Record(1, "a longer message here", "INFO")
				local many = _G.Record(2, "a longer message here", "INFO")
				many.count = 14
				return (many:dimensions()) - (one:dimensions())
			end)
		)
	end)
end)
