local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Covers docs/dev-specs/finder-lsp-exclude-current-position.md: the shared LSP source factory
-- (source/lsp.lua) must not emit a result whose file/line/column-range matches wherever the cursor
-- was when the jump was triggered. A real scratch buffer/window is used; only the vim.lsp.* entry
-- points are stubbed (in the child), so the fixture data is fully controlled.

local CUR_FILE = "/scratch/target.lua"

---@param lnum integer
---@param text string
---@param col integer
---@param end_col integer
local function qf(lnum, text, col, end_col)
	return { filename = CUR_FILE, lnum = lnum, col = col, end_col = end_col, text = text }
end

local PROFILE_REQUIRE = 'local profile = require("beast.profile")'

---Run the source with `qf_items` as the LSP answer and the cursor at `cursor`.
---@return { lines: integer[], idx: integer[], completed: boolean }
local function run(qf_items, cursor)
	return n.exec_lua(function(qf_items, cursor, cur_file)
		vim.lsp.util.locations_to_items = function()
			return qf_items
		end
		vim.api.nvim_win_set_cursor(_G.win, cursor)
		local items, completed = {}, false
		require("beast.libs.finder.source.lsp").create("textDocument/references", "References").get({ cur_win = _G.win, cwd = "/scratch" }, function(item)
			if item == nil then
				completed = true
			else
				items[#items + 1] = item
			end
		end)
		local out = { lines = {}, idx = {}, completed = completed }
		for i, item in ipairs(items) do
			out.lines[i] = item.pos[1]
			out.idx[i] = item.idx
		end
		return out
	end, qf_items, cursor, CUR_FILE)
end

t.describe("finder lsp source", function()
	t.before_each(function()
		h.clear()
		n.exec_lua(function(cur_file)
			local buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_name(buf, cur_file)
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
				"1",
				"2",
				"3",
				"4",
				'local profile = require("beast.profile")',
				"profile.start()",
				"profile.auto_dump_on_quit(out)",
			})
			vim.api.nvim_win_set_buf(0, buf)
			_G.win = vim.api.nvim_get_current_win()

			local fake_client = { id = 1, offset_encoding = "utf-16" }
			vim.lsp.get_clients = function()
				return { fake_client }
			end
			vim.lsp.get_client_by_id = function()
				return fake_client
			end
			vim.lsp.util.make_position_params = function()
				return {}
			end
			vim.lsp.buf_request_all = function(_, _, _, handler)
				handler({ [1] = { err = nil, result = { "dummy" } } })
			end
		end, CUR_FILE)
	end)

	-- "profile" spans byte columns 10..17 (0-indexed) on line 5.
	local both = {
		qf(5, PROFILE_REQUIRE, 11, 18),
		qf(6, "profile.start()", 1, 8),
	}

	t.describe("exact-column exclusion", function()
		t.it("emits only the other occurrence", function()
			t.eq(1, #run(both, { 5, 10 }).lines)
		end)

		t.it("emits line 6", function()
			t.eq(6, run(both, { 5, 10 }).lines[1])
		end)
	end)

	t.describe("mid-word exclusion", function()
		-- Cursor past the first character of "profile" (col 13 of 10..17), not on its start column.
		t.it("still emits only the other occurrence", function()
			t.eq(1, #run(both, { 5, 13 }).lines)
		end)

		t.it("emits line 6", function()
			t.eq(6, run(both, { 5, 13 }).lines[1])
		end)
	end)

	t.describe("all results excluded", function()
		t.it("emits no items", function()
			t.eq(0, #run({ qf(5, PROFILE_REQUIRE, 11, 18) }, { 5, 10 }).lines)
		end)

		t.it("still fires the completion callback", function()
			t.eq(true, run({ qf(5, PROFILE_REQUIRE, 11, 18) }, { 5, 10 }).completed)
		end)
	end)

	t.describe("no match for the cursor position", function()
		local r

		t.before_each(function()
			-- Cursor on line 1, nowhere near either result.
			r = run({ qf(6, "profile.start()", 1, 8), qf(7, "profile.auto_dump_on_quit(out)", 1, 8) }, { 1, 0 })
		end)

		t.it("emits both occurrences", function()
			t.eq(2, #r.lines)
		end)

		t.it("counts both in idx", function()
			t.eq(2, r.idx[2])
		end)
	end)
end)
