local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

local BOX_HEIGHT = 3

---Fill the current buffer with 40 lines, put the cursor on `line` and position the viewport.
---`view` is either a normal-mode scroll command ("zt"/"zz") or an exact topline number, which puts
---the cursor at a precise screen row (needed to hit the above/below boundary exactly).
---Then optionally set `buftype`, and return `position.resolve(BOX_HEIGHT)`.
---@param line integer
---@param view string|integer
---@param buftype? string
---@return { mode: string, anchor: string?, has_anchor: boolean }
local function resolve(line, view, buftype)
	return n.exec_lua(function(l, v, bt, box)
		vim.bo.buftype = ""
		local lines = {}
		for i = 1, 40 do
			lines[i] = "line " .. i
		end
		vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
		vim.api.nvim_win_set_cursor(0, { l, 0 })
		if type(v) == "string" then
			vim.cmd("normal! " .. v)
		else
			vim.fn.winrestview({ topline = v })
		end
		if bt ~= "" then
			vim.bo.buftype = bt
		end
		local result = require("beast.libs.input.position").resolve(box)
		return { mode = result.mode, anchor = result.anchor, has_anchor = result.anchor ~= nil }
	end, line, view, buftype or "", BOX_HEIGHT)
end

t.describe("input position", function()
	t.before_each(h.clear)

	t.describe("cursor-anchored", function()
		t.it("plenty of room above -> anchor SW", function()
			local r = resolve(20, "zz")
			t.eq("cursor", r.mode)
			t.eq("SW", r.anchor)
		end)

		t.it("no room above -> anchor NW (flip below)", function()
			local r = resolve(1, "zt")
			t.eq("cursor", r.mode)
			t.eq("NW", r.anchor)
		end)

		t.it("boundary: room_above exactly BOX_HEIGHT -> anchor SW", function()
			local r = resolve(20, 20 - BOX_HEIGHT)
			t.eq("cursor", r.mode)
			t.eq("SW", r.anchor)
		end)

		t.it("boundary: room_above one less than BOX_HEIGHT -> anchor NW", function()
			local r = resolve(20, 20 - (BOX_HEIGHT - 1))
			t.eq("cursor", r.mode)
			t.eq("NW", r.anchor)
		end)
	end)

	t.describe("centered fallback", function()
		t.it("special buftype", function()
			local r = resolve(20, "zz", "nofile")
			t.eq("center", r.mode)
			t.eq(false, r.has_anchor)
		end)

		t.it("current window is floating", function()
			local r = n.exec_lua(function(box)
				local buf = vim.api.nvim_create_buf(false, true)
				vim.api.nvim_open_win(buf, true, {
					relative = "editor",
					row = 0,
					col = 0,
					width = 10,
					height = 5,
					style = "minimal",
				})
				local result = require("beast.libs.input.position").resolve(box)
				return { mode = result.mode, has_anchor = result.anchor ~= nil }
			end, BOX_HEIGHT)
			t.eq({ mode = "center", has_anchor = false }, r)
		end)
	end)
end)
