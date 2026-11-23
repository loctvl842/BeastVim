local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

local KEY_UP = vim.api.nvim_replace_termcodes("<Up>", true, true, true)

---Run `skip.should_skip(cfg, ctx)` in the child, with `ctx` merged over sensible defaults.
---@param cfg table
---@param over table
---@return { skipped: boolean, override: string?, has_override: boolean, ok: boolean }
local function should_skip(cfg, over)
	return n.exec_lua(function(c, o)
		local ctx = vim.tbl_deep_extend("force", {
			open = "(",
			close = ")",
			neigh_pattern = "[^\\].",
			before = " ",
			after = " ",
			line = "",
			before_full = "",
			row = 1,
			col = 0,
		}, o)
		local ok, skipped, override = pcall(require("beast.libs.autopairs.skip").should_skip, c, ctx)
		return { ok = ok, skipped = skipped, override = override, has_override = override ~= nil }
	end, cfg, over)
end

t.describe("autopairs skip rules", function()
	t.before_each(h.clear)

	---@param cfg table
	---@param over table
	---@return boolean
	local function skipped(cfg, over)
		return should_skip(cfg, over).skipped
	end

	t.describe("skip_next", function()
		t.it("nil pattern never skips", function()
			t.eq(false, skipped({}, { after = "f" }))
		end)
		t.it("after='f' with [%w] skips", function()
			t.eq(true, skipped({ skip_next = "[%w]" }, { after = "f" }))
		end)
		t.it("after=' ' with [%w] does not skip", function()
			t.eq(false, skipped({ skip_next = "[%w]" }, { after = " " }))
		end)
		t.it("after='' (EOL) does not skip", function()
			t.eq(false, skipped({ skip_next = "[%w]" }, { after = "" }))
		end)
		-- LazyVim default set: alnum, %, ', [, ", ., `, $
		local lvz = { skip_next = [=[[%w%%%'%[%"%.%`%$]]=] }
		t.it("LazyVim pattern: after='.' skips", function()
			t.eq(true, skipped(lvz, { after = "." }))
		end)
		t.it("LazyVim pattern: after='$' skips", function()
			t.eq(true, skipped(lvz, { after = "$" }))
		end)
		t.it("LazyVim pattern: after=' ' does not skip", function()
			t.eq(false, skipped(lvz, { after = " " }))
		end)
	end)

	t.describe("skip_unbalanced", function()
		local cfg = { skip_unbalanced = true }

		t.it("after != close does not skip", function()
			t.eq(false, skipped(cfg, { after = "x", line = "((())" }))
		end)
		t.it("balanced line does not skip", function()
			t.eq(false, skipped(cfg, { after = ")", line = "()", open = "(", close = ")" }))
		end)
		t.it("more closers than openers skips", function()
			t.eq(true, skipped(cfg, { after = ")", line = "))) ", open = "(", close = ")" }))
		end)
		t.it("equal counts do not skip", function()
			t.eq(false, skipped(cfg, { after = ")", line = "()()", open = "(", close = ")" }))
		end)
		t.it("symmetric pair (quotes) never skips via unbalanced", function()
			t.eq(false, skipped(cfg, { after = '"', line = '""""""', open = '"', close = '"' }))
		end)
		t.it("flag off does not skip even when unbalanced", function()
			t.eq(false, skipped({ skip_unbalanced = false }, { after = ")", line = "))) ", open = "(", close = ")" }))
		end)
	end)

	t.describe("markdown fence expansion", function()
		---Run in a buffer of filetype `ft`.
		local function in_ft(ft, cfg, over)
			n.exec_lua(function(f)
				vim.cmd("enew")
				vim.bo.filetype = f
			end, ft)
			return should_skip(cfg, over)
		end

		t.it("two backticks + third expands to a fence", function()
			local r = in_ft("markdown", { markdown = true }, { open = "`", before_full = "``" })
			t.eq(true, r.skipped)
			t.eq("`\n```" .. KEY_UP, r.override)
		end)
		t.it("only one backtick does not expand", function()
			local r = in_ft("markdown", { markdown = true }, { open = "`", before_full = "`" })
			t.eq(false, r.skipped)
			t.eq(false, r.has_override)
		end)
		t.it("non-markdown filetype does not expand", function()
			local r = in_ft("lua", { markdown = true }, { open = "`", before_full = "``" })
			t.eq({ false, false }, { r.skipped, r.has_override })
		end)
		t.it("open != ` does not expand", function()
			local r = in_ft("markdown", { markdown = true }, { open = "(", before_full = "``" })
			t.eq({ false, false }, { r.skipped, r.has_override })
		end)
		t.it("markdown flag off does not expand", function()
			local r = in_ft("markdown", { markdown = false }, { open = "`", before_full = "``" })
			t.eq({ false, false }, { r.skipped, r.has_override })
		end)
	end)

	t.describe("skip_ts", function()
		---Lua buffer with the parser started; cursor at `pos`.
		---@param cfg table
		---@param row integer
		---@param col integer
		local function at(cfg, row, col)
			return n.exec_lua(function(c, r, cl)
				if not _G.ts_ready then
					vim.cmd("enew")
					vim.bo.filetype = "lua"
					vim.api.nvim_buf_set_lines(0, 0, -1, false, {
						'local s = "hello world"',
						"local n = 42",
					})
					assert(pcall(vim.treesitter.start, 0, "lua"), "lua treesitter parser unavailable")
					vim.treesitter.get_parser(0):parse()
					_G.ts_ready = true
				end
				vim.api.nvim_win_set_cursor(0, { r, cl })
				local skipped = require("beast.libs.autopairs.skip").should_skip(c, {
					open = "(",
					close = ")",
					neigh_pattern = "[^\\].",
					before = " ",
					after = " ",
					line = "",
					before_full = "",
					row = r,
					col = cl,
				})
				return skipped
			end, cfg, row, col)
		end

		t.it("inside a string literal skips", function()
			t.eq(true, at({ skip_ts = { "string" } }, 1, 18))
		end)
		t.it("inside code does not skip", function()
			t.eq(false, at({ skip_ts = { "string" } }, 2, 6))
		end)
		t.it("empty skip_ts list does not skip", function()
			t.eq(false, at({ skip_ts = {} }, 1, 18))
		end)
		t.it("multi-name list with a match skips", function()
			t.eq(true, at({ skip_ts = { "comment", "string" } }, 1, 18))
		end)
		t.it("buffer without a parser does not raise and does not skip", function()
			n.exec_lua(function()
				vim.cmd("enew")
				vim.bo.filetype = ""
			end)
			local r = should_skip({ skip_ts = { "string" } }, {})
			t.eq(true, r.ok)
			t.eq(false, r.skipped)
		end)
	end)

	t.describe("rule composition", function()
		t.it("markdown override beats skip_next when both could fire", function()
			n.exec_lua(function()
				vim.cmd("enew")
				vim.bo.filetype = "markdown"
			end)
			local r = should_skip({ skip_next = "[%w]", markdown = true }, { open = "`", before_full = "``", after = " " })
			t.eq({ true, true }, { r.skipped, r.has_override })
		end)
		t.it("pure skip_next path returns no override", function()
			n.exec_lua(function()
				vim.cmd("enew")
				vim.bo.filetype = "lua"
			end)
			local r = should_skip({ skip_next = "[%w]" }, { after = "f" })
			t.eq({ true, false }, { r.skipped, r.has_override })
		end)
	end)
end)
