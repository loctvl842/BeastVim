local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

t.describe("searchcount", function()
	t.before_each(h.clear)

	t.describe("format", function()
		---@param idx integer
		---@param total integer
		local function fmt(idx, total)
			return n.exec_lua(function(i, tot)
				return require("beast.libs.searchcount").format(i, tot)
			end, idx, total)
		end

		t.it("formats small counts as is", function()
			t.eq("2/3", fmt(2, 3))
		end)

		t.it("keeps the value at the cap", function()
			t.eq("999/999", fmt(999, 999))
		end)

		t.it("caps a total over the cap", function()
			t.eq("1/999+", fmt(1, 1000))
		end)

		t.it("caps both index and total over the cap", function()
			t.eq("999+/999+", fmt(5000, 12000))
		end)
	end)

	t.describe("get", function()
		t.before_each(function()
			n.exec_lua(function()
				vim.o.hlsearch = true
				vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local a", "", "x = local", "y", "local z" })
				_G.sc = require("beast.libs.searchcount")
				_G.win = vim.api.nvim_get_current_win()
			end)
		end)

		---Search for `pat` with the cursor at `pos`, refresh the cache, return get().text (or a nil flag).
		---@param pat string
		---@param pos integer[]
		---@param hl? integer v:hlsearch
		local function get(pat, pos, hl)
			return n.exec_lua(function(p, cursor, hls)
				vim.fn.setreg("/", p)
				vim.v.hlsearch = hls
				vim.api.nvim_win_set_cursor(_G.win, cursor)
				_G.sc.refresh(_G.win)
				local r = _G.sc.get(_G.win)
				return { found = r ~= nil, text = r and r.text }
			end, pat, pos, hl or 1)
		end

		t.it("is nil before any search", function()
			t.eq(true, n.exec_lua("return _G.sc.get(_G.win) == nil"))
		end)

		t.it("reports the first match", function()
			t.eq("1/3", get("local", { 1, 0 }).text)
		end)

		t.it("reports the second match", function()
			t.eq("2/3", get("local", { 3, 4 }).text)
		end)

		t.it("is nil when the cursor is off a match", function()
			t.eq(false, get("local", { 4, 0 }).found)
		end)

		t.it("is nil when highlight is cleared", function()
			t.eq(false, get("local", { 5, 0 }, 0).found)
		end)

		t.it("is nil when there are no matches", function()
			t.eq(false, get("zzz", { 5, 0 }).found)
		end)

		t.it("does not scan until refreshed", function()
			t.eq(
				{ before = true, after = "1/3" },
				n.exec_lua(function()
					vim.fn.setreg("/", "local")
					vim.v.hlsearch = 1
					vim.api.nvim_win_set_cursor(_G.win, { 1, 0 })
					local before = _G.sc.get(_G.win) == nil
					_G.sc.refresh(_G.win)
					return { before = before, after = _G.sc.get(_G.win).text }
				end)
			)
		end)

		t.it("drops the cache when the pattern changes", function()
			t.eq(
				true,
				n.exec_lua(function()
					vim.fn.setreg("/", "local")
					vim.v.hlsearch = 1
					vim.api.nvim_win_set_cursor(_G.win, { 1, 0 })
					_G.sc.refresh(_G.win)
					vim.fn.setreg("/", "x")
					return _G.sc.get(_G.win) == nil
				end)
			)
		end)

		t.it("drops the cache when the window shows another buffer", function()
			t.eq(
				true,
				n.exec_lua(function()
					vim.fn.setreg("/", "local")
					vim.v.hlsearch = 1
					vim.api.nvim_win_set_cursor(_G.win, { 1, 0 })
					_G.sc.refresh(_G.win)
					vim.api.nvim_win_set_buf(_G.win, vim.api.nvim_create_buf(true, true))
					return _G.sc.get(_G.win) == nil
				end)
			)
		end)

		t.it("refresh returns nil and clears the cache when highlight is off", function()
			t.eq(
				{ refreshed = true, cached = true },
				n.exec_lua(function()
					vim.fn.setreg("/", "local")
					vim.v.hlsearch = 1
					vim.api.nvim_win_set_cursor(_G.win, { 1, 0 })
					_G.sc.refresh(_G.win)
					vim.v.hlsearch = 0
					local refreshed = _G.sc.refresh(_G.win) == nil
					vim.v.hlsearch = 1
					return { refreshed = refreshed, cached = _G.sc.get(_G.win) == nil }
				end)
			)
		end)

		t.describe("setup", function()
			t.it("refreshes after the cursor moves and the debounce elapses", function()
				t.eq(
					{ immediate = true, settled = "2/3" },
					n.exec_lua(function()
						_G.sc.setup()
						vim.fn.setreg("/", "local")
						vim.v.hlsearch = 1
						vim.api.nvim_win_set_cursor(_G.win, { 1, 0 })
						_G.sc.refresh(_G.win)
						vim.api.nvim_win_set_cursor(_G.win, { 3, 4 })
						vim.api.nvim_exec_autocmds("CursorMoved", {})
						-- Still debouncing: the count for the old cursor must not be reported.
						local immediate = _G.sc.get(_G.win).text == "1/3"
						vim.wait(1000, function()
							local r = _G.sc.get(_G.win)
							return r ~= nil and r.text == "2/3"
						end)
						return { immediate = immediate, settled = _G.sc.get(_G.win).text }
					end)
				)
			end)

			t.it("collapses a burst of moves into one refresh", function()
				t.eq(
					1,
					n.exec_lua(function()
						_G.sc.setup()
						vim.fn.setreg("/", "local")
						vim.v.hlsearch = 1
						local calls = 0
						local orig = vim.fn.searchcount
						vim.fn.searchcount = function(...)
							calls = calls + 1
							return orig(...)
						end
						_G.sc.refresh(_G.win) -- seed, counts as one scan
						calls = 0
						for _ = 1, 20 do
							vim.api.nvim_exec_autocmds("CursorMoved", {})
						end
						vim.wait(500, function()
							return calls > 0
						end)
						vim.wait(200)
						vim.fn.searchcount = orig
						return calls
					end)
				)
			end)
		end)

		t.describe("past the cap", function()
			t.before_each(function()
				n.exec_lua(function()
					local many = {}
					for i = 1, 1500 do
						many[i] = "local x"
					end
					vim.api.nvim_buf_set_lines(0, 0, -1, false, many)
				end)
			end)

			t.it("caps index and total", function()
				t.eq("999+/999+", get("local", { 1200, 0 }).text)
			end)

			t.it("is nil when off a match", function()
				t.eq(false, get("local", { 1200, 3 }).found)
			end)
		end)
	end)
end)
