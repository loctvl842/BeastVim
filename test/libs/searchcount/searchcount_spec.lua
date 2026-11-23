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

		---Search for `pat` with the cursor at `pos`, return get().text (or a nil flag).
		---@param pat string
		---@param pos integer[]
		---@param hl? integer v:hlsearch
		local function get(pat, pos, hl)
			return n.exec_lua(function(p, cursor, hls)
				vim.fn.setreg("/", p)
				vim.v.hlsearch = hls
				vim.api.nvim_win_set_cursor(_G.win, cursor)
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
