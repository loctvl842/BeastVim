local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

t.describe("finder format", function()
	t.before_each(function()
		h.clear()
		-- Child-side probes used by the specs below. `text` is the rendered text of a row.
		n.exec_lua(function()
			_G.F = require("beast.libs.finder.format")
			_G.text = function(parts)
				local out = {}
				for _, p in ipairs(parts) do
					out[#out + 1] = p.text
				end
				return table.concat(out)
			end
			_G.cwd = vim.fn.getcwd()
			---Columns drawn for the item's `positions` on a rendered row.
			_G.columns = function(item, width)
				local list_buf = vim.api.nvim_create_buf(false, true)
				vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, { _G.text(_G.F.filename(item, width)) })
				require("beast.libs.finder.match_hl").apply_list(list_buf, { item }, function(it)
					return _G.F.filename(it, width)
				end, 1, 1, 1)
				return require("beast.libs.finder.match_hl").list_ranges(list_buf)[0] or {}
			end
		end)
	end)

	t.describe("file rows", function()
		t.it("shows a root file as base only, no dir", function()
			t.eq(
				{ no_gap = true, has_base = true },
				n.exec_lua(function()
					local txt = _G.text(_G.F.filename({ text = "init.lua", file = _G.cwd .. "/init.lua", cwd = _G.cwd }))
					return { no_gap = not txt:find("  ", 1, true), has_base = txt:find("init.lua", 1, true) ~= nil }
				end)
			)
		end)

		t.it("shows a nested file name first with the folder dim after", function()
			t.eq(
				true,
				n.exec_lua(function()
					local txt = _G.text(_G.F.filename({
						text = "lua/beast/a.lua",
						file = _G.cwd .. "/lua/beast/a.lua",
						cwd = _G.cwd,
					}))
					return txt:find("a.lua  lua/beast", 1, true) ~= nil
				end)
			)
		end)

		t.it("maps the dim folder to its source range", function()
			t.eq(
				{ text = "lua/beast", from = 1, to = 9 },
				n.exec_lua(function()
					local parts = _G.F.filename({
						text = "lua/beast/a.lua",
						file = _G.cwd .. "/lua/beast/a.lua",
						cwd = _G.cwd,
					})
					for _, p in ipairs(parts) do
						if p.hl == "BeastFinderListDir" then
							return { text = p.text, from = p.src[1], to = p.src[2] }
						end
					end
				end)
			)
		end)

		t.it("trims a long folder with an ellipsis and drops its source range", function()
			t.eq(
				{ ellipsis = true, has_dir = true, no_src = true },
				n.exec_lua(function()
					local long = "api-reference/beta/includes/snippets/csharp/file.md"
					local parts = _G.F.filename({ text = long, file = _G.cwd .. "/" .. long, cwd = _G.cwd }, 30)
					local dir
					for _, p in ipairs(parts) do
						if p.hl == "BeastFinderListDir" then
							dir = p
						end
					end
					return {
						ellipsis = _G.text(parts):find("…", 1, true) ~= nil,
						has_dir = dir ~= nil,
						no_src = dir ~= nil and dir.src == nil,
					}
				end)
			)
		end)

		t.it("renders the grep header as the same row", function()
			t.eq(
				true,
				n.exec_lua(function()
					local file = _G.cwd .. "/lua/beast/a.lua"
					local header = _G.F.live_grep_header({ file = file, cwd = _G.cwd })
					local row = _G.F.filename({ text = "lua/beast/a.lua", file = file, cwd = _G.cwd })
					return _G.text(header) == _G.text(row)
				end)
			)
		end)
	end)

	t.describe("buffer rows", function()
		t.it("has no [n] prefix and no [+] when clean", function()
			t.eq(
				{ no_prefix = true, no_plus = true },
				n.exec_lua(function()
					local b = vim.api.nvim_create_buf(true, false)
					vim.api.nvim_buf_set_name(b, _G.cwd .. "/zz_fmt_buf.lua")
					local clean = _G.text(_G.F.buffers({
						text = _G.cwd .. "/zz_fmt_buf.lua",
						file = _G.cwd .. "/zz_fmt_buf.lua",
						cwd = _G.cwd,
						buf = b,
					}))
					return {
						no_prefix = not clean:find("[" .. b .. "]", 1, true),
						no_plus = not clean:find("[+]", 1, true),
					}
				end)
			)
		end)

		t.it("ends a modified buffer with [+]", function()
			t.eq(
				" [+]",
				n.exec_lua(function()
					local b = vim.api.nvim_create_buf(true, false)
					vim.api.nvim_buf_set_name(b, _G.cwd .. "/zz_fmt_buf.lua")
					vim.api.nvim_buf_set_lines(b, 0, -1, false, { "x" })
					local dirty = _G.text(_G.F.buffers({
						text = _G.cwd .. "/zz_fmt_buf.lua",
						file = _G.cwd .. "/zz_fmt_buf.lua",
						cwd = _G.cwd,
						buf = b,
					}))
					return dirty:sub(-4)
				end)
			)
		end)

		t.it("renders a nameless buffer plain", function()
			t.eq(
				"[No Name]",
				n.exec_lua(function()
					local nameless = _G.F.buffers({
						text = "[No Name] 9",
						cwd = _G.cwd,
						buf = vim.api.nvim_create_buf(true, false),
					})
					return _G.text(nameless)
				end)
			)
		end)
	end)

	t.describe("highlight mapping", function()
		---Run `positions` (1-based indexes of item.text) through the child and report the drawn ranges
		---with the columns where the base name and the folder sit in the row.
		---@param positions integer[]
		---@param width? integer
		---@param text? string item text (default "lua/beast/a.lua")
		local function drawn(positions, width, text)
			return n.exec_lua(function(args)
				local pos, w, txt = args.positions, args.width, args.text
				local item = { text = txt, file = _G.cwd .. "/" .. txt, cwd = _G.cwd, positions = pos }
				local row = _G.text(_G.F.filename(item, w))
				return {
					ranges = _G.columns(item, w),
					base_col = (row:find("a.lua", 1, true) or 1) - 1,
					dir_col = (row:find("lua/beast", 1, true) or 1) - 1,
				}
			end, { positions = positions, width = width, text = text or "lua/beast/a.lua" })
		end

		t.it("lands a base match on the file name", function()
			local r = drawn({ 11 })
			t.eq({ r.base_col, r.base_col + 1 }, { r.ranges[1][1], r.ranges[1][2] })
		end)

		t.it("lands a folder match on the folder", function()
			local r = drawn({ 1, 2, 3 })
			t.eq({ r.dir_col, r.dir_col + 3 }, { r.ranges[1][1], r.ranges[1][2] })
		end)

		t.it("draws a match across the boundary as two ranges", function()
			t.eq(2, #drawn({ 8, 9, 10, 11 }).ranges)
		end)

		t.it("draws nothing for a match on the dropped slash", function()
			t.eq(0, #drawn({ 10 }).ranges)
		end)

		t.it("draws nothing for a match in a trimmed folder", function()
			t.eq(0, #drawn({ 20 }, 30, "api-reference/beta/includes/snippets/csharp/file.md").ranges)
		end)

		t.it("maps absolute buffer text through the cwd prefix", function()
			t.eq(
				true,
				n.exec_lua(function()
					local abs = { text = _G.cwd .. "/lua/a.lua", file = _G.cwd .. "/lua/a.lua", cwd = _G.cwd }
					abs.positions = { #_G.cwd + 2 + 4 } -- the "a" of a.lua inside the absolute text
					local buf_list = vim.api.nvim_create_buf(false, true)
					local function fmt(it)
						return _G.F.buffers(it)
					end
					require("beast.libs.finder.match_hl").apply_list(buf_list, { abs }, fmt, 1, 1, 1)
					local abs_row = _G.text(fmt(abs))
					local r = require("beast.libs.finder.match_hl").list_ranges(buf_list)[0] or {}
					return r[1] ~= nil and r[1][1] == abs_row:find("a.lua", 1, true) - 1
				end)
			)
		end)
	end)

	t.describe("titles", function()
		local long = "PR Refactor the finder so that every pic... › 0000001 Add chain table › Files Changed (12)"

		t.it("keeps a short title", function()
			t.eq(
				"PR x › Commits (4)",
				n.exec_lua(function()
					return _G.F.trim_middle("PR x › Commits (4)", 40)
				end)
			)
		end)

		t.it("fits a long title to the width", function()
			t.eq(
				40,
				n.exec_lua(function(s)
					return vim.fn.strdisplaywidth(_G.F.trim_middle(s, 40))
				end, long)
			)
		end)

		t.it("replaces the middle with ... and keeps the start", function()
			local fitted = n.exec_lua(function(s)
				return _G.F.trim_middle(s, 40)
			end, long)
			t.eq(true, fitted:find("...", 1, true) ~= nil and fitted:sub(1, 6) == "PR Ref")
		end)

		t.it("keeps the end (the count)", function()
			local fitted = n.exec_lua(function(s)
				return _G.F.trim_middle(s, 40)
			end, long)
			t.eq(true, fitted:sub(-13) == "Changed (12)" or fitted:find("Files Changed (12)", 1, true) ~= nil or fitted:sub(-6) == "d (12)")
		end)

		t.it("shortens a long commit subject in the label", function()
			t.eq(
				"abc1234 " .. ("x"):rep(27) .. "...",
				n.exec_lua(function()
					return _G.F.commit_label({ short = "abc1234", subject = ("x"):rep(50) })
				end)
			)
		end)
	end)
end)
