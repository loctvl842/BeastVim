local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Tabline edge-trim truncation.
t.describe("tabline edge trim", function()
	t.before_each(function()
		h.clear()
		n.exec_lua(function()
			--- Strip tabline highlight groups and click regions, returning visible text.
			_G.strip_hl = function(s)
				s = s:gsub("%%%d+@[^@]+@", "") -- %@...@ click regions
				s = s:gsub("%%X", "") -- close click region
				s = s:gsub("%%#[^#]+#", "") -- highlight groups
				s = s:gsub("%%=", "") -- right-align
				return s
			end

			---Open `files` as listed buffers.
			_G.open_files = function(files)
				for _, f in ipairs(files) do
					pcall(vim.cmd.edit, f)
				end
			end

			---@return integer[] listed buffers, sorted
			_G.listed = function()
				local out = vim.tbl_filter(function(b)
					return vim.bo[b].buflisted
				end, vim.api.nvim_list_bufs())
				table.sort(out)
				return out
			end

			---Build a tabline context for `anchor` and inject a 1-column icon per buffer
			---(the production devicons width).
			_G.build_ctx = function(anchor, columns, min_cell_w, sidebar_width)
				require("beast.libs.tabline.config").setup({ min_cell_width = min_cell_w })
				local ctx = require("beast.libs.tabline.context").build({ last_active_bufnr = anchor, last_diag_by_buf = nil })
				ctx.columns = columns -- simulate a narrow terminal
				ctx.tabpages_width = 0
				if sidebar_width then
					ctx.sidebar_width = sidebar_width
				end
				for _, bufnr in ipairs(ctx.listed_buffers) do
					ctx.icons_by_buf[bufnr] = { icon = "*", color = "#51a0cf" }
				end
				return ctx
			end

			---Render the buffer list and report widths.
			_G.render = function(ctx)
				local rendered, visible, left_hidden, right_hidden = require("beast.libs.tabline.sections.buffer_list").render(ctx)
				local display_w = vim.fn.strdisplaywidth(_G.strip_hl(rendered))
				local available = ctx.columns - (ctx.sidebar_width or 0) - ctx.tabpages_width - ctx.toggle_button_width - ctx.visibility_width
				return {
					display_w = display_w,
					available = available,
					waste = available - display_w,
					visible = #visible,
					left_hidden = left_hidden,
					right_hidden = right_hidden,
				}
			end

			---First listed buffer whose name matches the Lua `pattern`.
			_G.find_buf = function(pattern)
				for _, b in ipairs(_G.listed()) do
					if vim.api.nvim_buf_get_name(b):match(pattern) then
						return b
					end
				end
			end

			-- Duplicate basenames (init.lua) get a parent-dir label, so the cell width
			-- depends on the cwd name: pin it to keep the scenarios independent of where
			-- the repo is checked out ("nvim" matches the user report they reproduce).
			_G.enter_scenario_dir = function()
				local dir = vim.fn.tempname() .. "/nvim"
				vim.fn.mkdir(dir, "p")
				vim.cmd.cd(dir)
			end
		end)
	end)

	t.describe("name.truncate_text_end", function()
		---@param text string
		---@param width integer
		local function trunc_end(text, width)
			return n.exec_lua(function(s, w)
				return require("beast.libs.tabline.name").truncate_text_end(s, w)
			end, text, width)
		end

		t.it("puts the ellipsis at the end", function()
			t.eq("hell…", trunc_end("hello.lua", 5))
		end)

		t.it("leaves text that fits", function()
			t.eq("hi", trunc_end("hi", 5))
		end)

		t.it("collapses to the ellipsis at max_width=1", function()
			t.eq("…", trunc_end("hello", 1))
		end)

		t.it("is empty at max_width=0", function()
			t.eq("", trunc_end("hello", 0))
		end)

		t.it("keeps an exact fit", function()
			t.eq("abc", trunc_end("abc", 3))
		end)
	end)

	t.describe("name.truncate_text (leading ellipsis, sanity check)", function()
		t.it("puts the ellipsis at the start", function()
			t.eq(
				"….lua",
				n.exec_lua(function()
					return require("beast.libs.tabline.name").truncate_text("hello.lua", 5)
				end)
			)
		end)

		t.it("leaves text that fits", function()
			t.eq(
				"hi",
				n.exec_lua(function()
					return require("beast.libs.tabline.name").truncate_text("hi", 5)
				end)
			)
		end)
	end)

	t.describe("with min_cell_width (the bug scenario)", function()
		-- 12 known buffers, anchored in the middle.
		---@param columns integer
		---@param min_cell integer
		---@return table
		local function run(columns, min_cell)
			return n.exec_lua(function(cols, min_w)
				local files = {}
				for i = 1, 12 do
					files[i] = string.format("test_buf_%02d.lua", i)
				end
				_G.open_files(files)
				local listed = _G.listed()
				local anchor = listed[math.ceil(#listed / 2)]
				return _G.render(_G.build_ctx(anchor, cols, min_w))
			end, columns, min_cell)
		end

		local cases = {
			{ "no min_cell_width, wide", 200, 0 },
			{ "no min_cell_width, narrow", 80, 0 },
			{ "no min_cell_width, very narrow", 40, 0 },
			{ "min_cell_width=18, wide", 200, 18 },
			{ "min_cell_width=18, medium", 181, 18 },
			{ "min_cell_width=18, narrow", 120, 18 },
			{ "min_cell_width=18, very narrow", 60, 18 },
			{ "min_cell_width=25, medium", 150, 25 },
			{ "min_cell_width=25, narrow", 80, 25 },
			{ "no truncation needed", 500, 0 },
			{ "no truncation needed with min_cell", 500, 18 },
		}
		for _, case in ipairs(cases) do
			local name, columns, min_cell = case[1], case[2], case[3]
			t.it(("%s (cols=%d, min_cell=%d) fits the available width"):format(name, columns, min_cell), function()
				local r = run(columns, min_cell)
				t.eq(true, r.display_w <= r.available)
			end)

			t.it(("%s (cols=%d, min_cell=%d) wastes less than a cell overhead"):format(name, columns, min_cell), function()
				local r = run(columns, min_cell)
				-- Structural waste can be up to ~overhead (7-9) when the next cell can't fit.
				if r.left_hidden > 0 or r.right_hidden > 0 then
					t.eq(true, r.waste < 12)
				end
			end)
		end
	end)

	t.describe("fit_around_anchor", function()
		t.it("returns a positive total_width equal to the sum of the visible estimates", function()
			t.eq(
				{ is_number = true, positive = true, matches_sum = true },
				n.exec_lua(function()
					local files = {}
					for i = 1, 12 do
						files[i] = string.format("test_buf_%02d.lua", i)
					end
					_G.open_files(files)
					local listed = _G.listed()
					local ctx = _G.build_ctx(listed[1], 80) -- default config
					local truncate = require("beast.libs.tabline.truncate")
					local function est_fn(bufnr, is_anchor)
						return truncate.estimate_cell_width(bufnr, ctx, is_anchor)
					end
					local visible, _, _, tw = truncate.fit_around_anchor({}, listed[1], vim.list_slice(listed, 2), est_fn, 500)
					local sum = 0
					for i, bufnr in ipairs(visible) do
						sum = sum + est_fn(bufnr, i == 1 and bufnr == listed[1])
					end
					return { is_number = type(tw) == "number", positive = tw > 0, matches_sum = tw == sum }
				end)
			)
		end)
	end)

	---Open `files` in a pinned scenario dir, anchor on the buffer matching `pattern`, render at
	---181 columns with min_cell_width=18.
	---@param files string[]
	---@param pattern string
	---@param sidebar? integer
	local function scenario(files, pattern, sidebar)
		return n.exec_lua(function(f, pat, sb)
			_G.enter_scenario_dir()
			_G.open_files(f)
			local anchor = _G.find_buf(pat)
			if anchor then
				pcall(vim.api.nvim_set_current_buf, anchor)
			end
			return _G.render(_G.build_ctx(anchor, 181, 18, sb))
		end, files, pattern, sidebar)
	end

	local main_files = {
		"commit.lua",
		"init.lua",
		"nvim-pack-lock.json",
		"sample_ui_finder",
		"SKILL.md",
		"stylua.toml",
		"lua/beast/icon.lua",
		"lua/beast/init.lua",
		"lua/beast/option.lua",
		"lua/beast/palette.lua",
		"lua/beast/profile.lua",
	}

	t.describe("exact user scenario (left-only truncation, min_cell=18)", function()
		local r
		t.before_each(function()
			r = scenario({
				"lua/beast/libs/animate.lua",
				"lua/beast/libs/async.lua",
				"lua/beast/libs/buf.lua",
				"lua/beast/libs/view.lua",
				"lua/beast/icon.lua",
				"lua/beast/init.lua",
				"lua/beast/option.lua",
				"lua/beast/palette.lua",
				"lua/beast/profile.lua",
				"commit.lua",
				"init.lua",
				"nvim-pack-lock.json",
			}, "commit%.lua$")
		end)

		t.it("fits the available width", function()
			t.eq(true, r.display_w <= r.available)
		end)

		t.it("leaves no large gap (edge-trimmed cell uses the freed space)", function()
			t.eq(true, r.waste < 10)
		end)

		t.it("shows at least 9 buffers", function()
			t.eq(true, r.visible >= 9)
		end)
	end)

	t.describe("SKILL.md anchor (both-side truncation, min_cell=18)", function()
		local r
		t.before_each(function()
			r = scenario({
				"commit.lua",
				"init.lua",
				"nvim-pack-lock.json",
				"sample_ui_finder",
				"SKILL.md",
				"stylua.toml",
				"lua/beast/icon.lua",
				"lua/beast/init.lua",
				"lua/beast/option.lua",
				"lua/beast/palette.lua",
				"lua/beast/profile.lua",
			}, "SKILL%.md$")
		end)

		t.it("fits the available width", function()
			t.eq(true, r.display_w <= r.available)
		end)

		t.it("wastes less than a cell overhead", function()
			t.eq(true, r.waste < 8)
		end)

		t.it("pulls in an extra cell (at least 8 buffers visible)", function()
			t.eq(true, r.visible >= 8)
		end)
	end)

	t.describe("commit.lua selected first, right-only truncation", function()
		local r
		t.before_each(function()
			r = scenario({
				"commit.lua",
				"init.lua",
				"nvim-pack-lock.json",
				"sample_ui_finder",
				"SKILL.md",
				"stylua.toml",
				"lua/beast/icon.lua",
				"lua/beast/init.lua",
				"lua/beast/option.lua",
				"lua/beast/palette.lua",
				"lua/beast/profile.lua",
				"lua/beast/libs/animate.lua",
				"lua/beast/libs/async.lua",
				"lua/beast/libs/buf.lua",
				"lua/beast/libs/view.lua",
			}, "commit%.lua$")
		end)

		t.it("fits the available width", function()
			t.eq(true, r.display_w <= r.available)
		end)

		t.it("wastes less than a cell overhead", function()
			t.eq(true, r.waste < 8)
		end)

		t.it("has no left truncation", function()
			t.eq(0, r.left_hidden)
		end)
	end)

	t.describe("sample_ui_finder anchor with explorer sidebar", function()
		local r
		t.before_each(function()
			r = scenario(main_files, "sample_ui_finder$", 40)
		end)

		t.it("fits the available width", function()
			t.eq(true, r.display_w <= r.available)
		end)

		t.it("fills tightly (waste < compact overhead)", function()
			t.eq(true, r.waste < 4)
		end)

		t.it("shows at least 6 buffers (5 full + 1 compact pull-in)", function()
			t.eq(true, r.visible >= 6)
		end)
	end)

	t.describe("beast/init.lua anchor, sidebar, left-only truncation", function()
		local r
		t.before_each(function()
			r = scenario(main_files, "lua/beast/init%.lua$", 40)
		end)

		t.it("fits the available width", function()
			t.eq(true, r.display_w <= r.available)
		end)

		t.it("wastes less than a compact overhead", function()
			t.eq(true, r.waste < 5)
		end)

		t.it("has no right truncation (profile.lua is last)", function()
			t.eq(0, r.right_hidden)
		end)

		t.it("pulls in a buffer on the left via compact (at least 7 visible)", function()
			t.eq(true, r.visible >= 7)
		end)
	end)
end)
