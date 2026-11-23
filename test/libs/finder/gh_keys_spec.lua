local F = require("test.libs.finder.helpers.finder")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Finder keys on GitHub rows (and unchanged behaviour on file rows): Enter opens the URL, <C-y> copies
-- it, message rows ignore both, <C-s>/<C-v> keep the picker open for rows without a file but still
-- open files for file rows.

local PR = { idx = 1, score = 1, text = "#1 t", url = "https://github.com/o/n/pull/1" }
local MSG = { idx = 1, score = 1, text = "No results for this search", message = true }
local FILE = { idx = 1, score = 1, text = "a.lua", file = "/tmp/a.lua" }

---Open the picker on a single `item`, press `lhs` in the prompt.
---@param item table
---@param lhs string
---@return boolean mapped whether the prompt maps `lhs`
---@return boolean open whether the picker is still open afterwards
local function press(item, lhs)
	n.exec_lua(function(it)
		_G.row = it
	end, item)
	F.close()
	F.open("fake_keys")
	local mapped = F.press(lhs)
	return mapped, F.window_count() > 0
end

---The list's selection state: cursorline and the selection marker.
---@return { cursorline: boolean, marker: boolean }
local function list_state()
	return n.exec_lua(function()
		local list = FH.panes().list
		local marker = false
		for _, m in ipairs(vim.api.nvim_buf_get_extmarks(list.buf, -1, 0, -1, { details = true })) do
			local vt = m[4].virt_text
			if vt and vt[1] and vt[1][1]:find("▌", 1, true) then
				marker = true
			end
		end
		return { cursorline = vim.wo[list.win].cursorline, marker = marker }
	end)
end

t.describe("finder gh keys", function()
	t.before_each(function()
		F.setup()
		n.exec_lua(function()
			_G.opened_urls = {}
			_G.split_calls = {}
			---@diagnostic disable-next-line: duplicate-set-field
			vim.ui.open = function(url)
				_G.opened_urls[#_G.opened_urls + 1] = url
				return {}, nil
			end
			local action = require("beast.libs.finder.action")
			action.open_split = function(_, item)
				_G.split_calls[#_G.split_calls + 1] = "split:" .. item.file
			end
			action.open_vsplit = function(_, item)
				_G.split_calls[#_G.split_calls + 1] = "vsplit:" .. item.file
			end
			-- The row the next search returns; the test swaps it between cases.
			FH.fake_source("fake_keys", {
				live = true,
				async = true,
				initial_query = "q",
				run_when_empty = true,
				debounce_ms = 10,
				get = function(_, cb)
					cb(_G.row)
					cb(nil)
				end,
				cancel = function() end,
			})
		end)
	end)

	t.after_each(F.close)

	---@return string[]
	local function opened()
		return n.exec_lua(function()
			return _G.opened_urls
		end)
	end

	---@return string[]
	local function splits()
		return n.exec_lua(function()
			return _G.split_calls
		end)
	end

	t.describe("message rows", function()
		t.it("have no selection marker", function()
			n.exec_lua(function(item)
				_G.row = item
			end, MSG)
			F.open("fake_keys")
			t.eq(false, list_state().marker)
		end)

		t.it("have no cursorline", function()
			n.exec_lua(function(item)
				_G.row = item
			end, MSG)
			F.open("fake_keys")
			t.eq(false, list_state().cursorline)
		end)
	end)

	t.describe("normal rows", function()
		t.it("have the selection marker", function()
			n.exec_lua(function(item)
				_G.row = item
			end, PR)
			F.open("fake_keys")
			t.eq(true, list_state().marker)
		end)

		t.it("have the cursorline", function()
			n.exec_lua(function(item)
				_G.row = item
			end, PR)
			F.open("fake_keys")
			t.eq(true, list_state().cursorline)
		end)
	end)

	t.describe("Enter", function()
		t.it("on a message row keeps the picker open and opens nothing", function()
			local mapped, open = press(MSG, "<CR>")
			t.eq(true, mapped)
			t.eq(true, open)
			t.eq({}, opened())
		end)

		t.it("on a url row closes the picker and opens the url in the browser", function()
			local mapped, open = press(PR, "<CR>")
			t.eq(true, mapped)
			t.eq(false, open)
			t.eq({ PR.url }, opened())
		end)
	end)

	t.describe("Ctrl-y", function()
		t.before_each(function()
			n.exec_lua(function()
				vim.fn.setreg("+", "untouched")
			end)
		end)

		---@return string
		local function clipboard()
			return n.exec_lua(function()
				return vim.fn.getreg("+")
			end)
		end

		t.it("keeps the picker open and copies the url", function()
			local mapped, open = press(PR, "<C-y>")
			t.eq(true, mapped)
			t.eq(true, open)
			t.eq(PR.url, clipboard())
		end)

		t.it("confirms with a toast", function()
			press(PR, "<C-y>")
			t.eq("Copied: " .. PR.url, F.last_toast())
		end)

		t.it("on a message row copies nothing", function()
			press(MSG, "<C-y>")
			t.eq("untouched", clipboard())
		end)
	end)

	t.describe("splits", function()
		t.it("<C-s> on a url row keeps the picker open", function()
			local mapped, open = press(PR, "<C-s>")
			t.eq(true, mapped)
			t.eq(true, open)
		end)

		t.it("<C-v> on a url row keeps the picker open", function()
			local mapped, open = press(PR, "<C-v>")
			t.eq(true, mapped)
			t.eq(true, open)
		end)

		t.it("split nothing on url rows", function()
			press(PR, "<C-s>")
			press(PR, "<C-v>")
			t.eq({}, splits())
		end)

		t.it("<C-s> on a file row closes the picker and splits the file", function()
			local mapped, open = press(FILE, "<C-s>")
			t.eq(true, mapped)
			t.eq(false, open)
			t.eq({ "split:/tmp/a.lua" }, splits())
		end)

		t.it("<C-v> on a file row closes the picker and vsplits the file", function()
			local mapped, open = press(FILE, "<C-v>")
			t.eq(true, mapped)
			t.eq(false, open)
			t.eq({ "vsplit:/tmp/a.lua" }, splits())
		end)
	end)
end)
