local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- A closed fold shows only its first row. The sticky context header must show
-- the same rows instead of expanding the folded parameters.

-- Parsers and context queries installed by the real config (NVIM_APPNAME=BeastVim) live outside
-- the harness runtimepath, and the harness redirects stdpath("data").
local DATA_HOME = vim.env.HOME .. "/.local/share"

t.describe("treesitter context header with folds", function()
	t.before_each(function()
		h.clear()
		local available = n.exec_lua(function(data_home)
			-- The context query loader reads stdpath("data")/site: point it at the real install.
			vim.env.XDG_DATA_HOME = data_home
			vim.env.NVIM_APPNAME = "BeastVim"
			vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/site")
			local has_parser = pcall(vim.treesitter.get_string_parser, "", "python")
			local has_query = has_parser and require("beast.libs.treesitter.context.query").has("python")
			-- Build a function whose header spans lines 1-4 and a body tall enough that
			-- the header scrolls out of view.
			_G.open = function(fold)
				local lines = { "def f(", "    a,", "    b,", "):" }
				for i = 1, 40 do
					lines[#lines + 1] = "    x_" .. i .. " = " .. i
				end
				local buf = vim.api.nvim_create_buf(false, true)
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
				vim.api.nvim_set_current_buf(buf)
				vim.treesitter.start(buf, "python")
				vim.wo.foldmethod = "manual"
				vim.wo.foldenable = true
				vim.wo.scrolloff = 0
				if fold then
					-- Close the parameter list, starting on the declaration line so the
					-- fold start matches the context header start.
					vim.cmd("1,3fold")
				end
				vim.cmd("normal! G")
				return buf, vim.api.nvim_get_current_win()
			end
			---@param ranges Range4[]
			---@param lines string[]
			_G.spans_match_lines = function(ranges, lines)
				local total = 0
				for _, range in ipairs(ranges) do
					total = total + (range[3] - range[1])
				end
				return total == #lines
			end
			return has_parser and has_query
		end, DATA_HOME)
		if not available then
			t.pending("python parser or context query unavailable")
		end
	end)

	t.describe("with a closed fold", function()
		t.it("closes the fold over lines 1-3 only", function()
			t.eq(
				{ 1, 1, 1, -1 },
				n.exec_lua(function()
					_G.open(true)
					return { vim.fn.foldclosed(1), vim.fn.foldclosed(2), vim.fn.foldclosed(3), vim.fn.foldclosed(4) }
				end)
			)
		end)

		t.it("shows only visible header rows, split into contiguous segments", function()
			t.eq(
				{
					lines = { "def f(", "):" },
					ranges = { { 0, 0, 1, 0 }, { 3, 0, 4, 0 } },
					spans_match = true,
				},
				n.exec_lua(function()
					local _, win = _G.open(true)
					local ranges, lines = require("beast.libs.treesitter.context.context").get(win)
					return { lines = lines, ranges = ranges, spans_match = _G.spans_match_lines(ranges, lines) }
				end)
			)
		end)

		t.it("paints the fold row with Folded below the syntax captures, keeping its syntax highlights", function()
			-- Render and inspect the float: the fold row must carry Folded and no
			-- syntax highlight, mirroring the source window's closed fold line.
			t.eq(
				{ found = true, folded = true, priority = 0, syntax = true },
				n.exec_lua(function()
					local buf, win = _G.open(true)
					local ranges, lines = require("beast.libs.treesitter.context.context").get(win)
					vim.treesitter.get_parser(buf):parse()
					local render = require("beast.libs.treesitter.context.render")
					render.open(win, ranges, lines, true)
					local ctx_buf
					for _, b in ipairs(vim.api.nvim_list_bufs()) do
						if vim.bo[b].filetype == "beast-treesitter-context" and vim.deep_equal(vim.api.nvim_buf_get_lines(b, 0, -1, false), lines) then
							ctx_buf = b
							break
						end
					end
					if not ctx_buf then
						return { found = false }
					end
					local ns = vim.api.nvim_get_namespaces()["beastvim_treesitter_context"]
					local folded_prio, syntax_marks = nil, 0
					for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(ctx_buf, ns, 0, -1, { details = true })) do
						if mark[2] == 0 then
							local hl = mark[4].hl_group
							if hl == "Folded" then
								folded_prio = mark[4].priority
							end
							if type(hl) == "string" and hl:sub(1, 1) == "@" then
								syntax_marks = syntax_marks + 1
							end
						end
					end
					render.close(win)
					return { found = true, folded = folded_prio ~= nil, priority = folded_prio, syntax = syntax_marks > 0 }
				end)
			)
		end)
	end)

	t.describe("with folds open (control)", function()
		t.it("shows all header rows as a single segment", function()
			t.eq(
				{
					lines = { "def f(", "    a,", "    b,", "):" },
					ranges = { { 0, 0, 4, 0 } },
					spans_match = true,
				},
				n.exec_lua(function()
					local _, win = _G.open(false)
					local ranges, lines = require("beast.libs.treesitter.context.context").get(win)
					return { lines = lines, ranges = ranges, spans_match = _G.spans_match_lines(ranges, lines) }
				end)
			)
		end)
	end)
end)
