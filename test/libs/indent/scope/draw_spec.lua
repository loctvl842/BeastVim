local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Installed parsers live under the real config's site dir (the harness redirects stdpath("data")).
local SITE = vim.env.HOME .. "/.local/share/BeastVim/site"

-- The scope line must sit at the indent of the opener line, even when the body's first line is off
-- grid (15 or 17 columns with shiftwidth 4, for example) or the header is wrapped. Captures the column
-- passed to nvim_buf_set_extmark instead of reading the screen.

t.describe("indent scope draw column", function()
	t.before_each(function()
		h.clear()
		n.exec_lua(function(site)
			vim.opt.runtimepath:append(site)
		end, SITE)
	end)

	---Render the scope for a scratch buffer and return the buffer columns the vertical line is drawn at.
	---@param lines string[]
	---@param sw integer
	---@param pos {[1]: integer, [2]: integer}
	---@param use_ts boolean
	---@return { missing: boolean?, cols: integer[]? }
	local function draw_cols(lines, sw, pos, use_ts)
		return n.exec_lua(function(l, shiftwidth, p, ts)
			if ts and not pcall(vim.treesitter.get_string_parser, "", "python") then
				return { missing = true }
			end
			local config = require("beast.libs.indent.config")
			local scope = require("beast.libs.indent.scope")
			config.setup({ scope = { treesitter = { enabled = ts } } })
			local buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, l)
			vim.bo[buf].shiftwidth = shiftwidth
			vim.bo[buf].tabstop = shiftwidth
			vim.bo[buf].expandtab = true
			vim.api.nvim_set_current_buf(buf)
			if ts then
				vim.treesitter.start(buf, "python")
			end
			vim.api.nvim_win_set_cursor(0, p)
			scope.update(function()
				return false
			end)
			vim.wait(200)

			local win = vim.api.nvim_get_current_win()
			local cols = {}
			local real = vim.api.nvim_buf_set_extmark
			vim.api.nvim_buf_set_extmark = function(_, _, _, _, extmark_opts)
				if extmark_opts and extmark_opts.virt_text_win_col then
					cols[extmark_opts.virt_text_win_col] = true
				end
				return 0
			end
			-- draw runs inside nvim_buf_call in the decoration provider
			vim.api.nvim_buf_call(buf, function()
				scope.draw(buf, 1, win, 1, #l, 0, shiftwidth)
			end)
			vim.api.nvim_buf_set_extmark = real

			local result = vim.tbl_keys(cols)
			table.sort(result)
			return { cols = result }
		end, lines, sw, pos, use_ts)
	end

	---@param name string
	---@param lines string[]
	---@param pos {[1]: integer, [2]: integer}
	---@param expected integer[]
	---@param use_ts? boolean
	local function check(name, lines, pos, expected, use_ts)
		t.it(name, function()
			local r = draw_cols(lines, 4, pos, use_ts ~= false)
			if r.missing then
				t.pending("no python parser")
			end
			t.eq(expected, r.cols)
		end)
	end

	t.describe("scope line anchored to the opener", function()
		-- Body first line at 7 with shiftwidth 4: line belongs at the opener indent 4, not 3 (indent - shiftwidth).
		check("under-indented body keeps the opener column", {
			"def f():",
			"    if a:",
			"       pass",
		}, { 2, 4 }, { 4 })

		-- Body first line at 17 (one past the aligned 16): still the opener indent 4, not 13 or 16 (a grid snap).
		check("over-indented body keeps the opener column", {
			"def f():",
			"    if a:",
			"                 pass",
		}, { 2, 4 }, { 4 })

		-- Aligned body: same result as before the change (indent 8 - shiftwidth 4 = 4).
		check("aligned body keeps the opener column", {
			"def f():",
			"    if a:",
			"        pass",
		}, { 2, 4 }, { 4 })

		-- Body indent below one shiftwidth: the opener is at column 0.
		check("body shallower than shiftwidth draws at column 0", {
			"if a:",
			" pass",
		}, { 1, 0 }, { 0 })

		-- Wrapped header: the line directly above the body is a continuation at 12, so the anchor must
		-- be the node's first line (the `def` at 4), not from - 1.
		check("wrapped header anchors to the first header line", {
			"class A:",
			"    def add(",
			"            self):",
			"        pass",
		}, { 2, 4 }, { 4 })

		-- Same off-grid body through the indent fallback (no treesitter).
		check("indent strategy anchors to the opener too", {
			"def f():",
			"    if a:",
			"          pass",
		}, { 2, 4 }, { 4 }, false)
	end)
end)
