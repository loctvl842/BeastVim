local F = require("test.libs.finder.helpers.finder")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Per-source behavior: row format, grouping, Enter action, reload, preview hook. Uses the real source
-- modules (names, formats, open behavior) with their data producers replaced by fixed items, and
-- drives the real picker. Characterizes today's name-based behavior so moving it onto the sources
-- (docs/dev-specs/finder-levels-refactor.md, phase 2) cannot change it.

---Run `fn(...)` in the child.
local function child(fn, ...)
	return n.exec_lua(fn, ...)
end

---Count rows matching `^%d+:%d+` (grep match rows) and the remaining non-empty ones (file headers).
---@return integer headers
---@return integer matches
local function count_rows()
	local headers, matches = 0, 0
	for _, row in ipairs(F.rows()) do
		if row:match("^%d+:%d+") then
			matches = matches + 1
		elseif row ~= "" then
			headers = headers + 1
		end
	end
	return headers, matches
end

t.describe("finder source behavior", function()
	t.before_each(function()
		F.setup()
		child(function()
			-- The colorscheme source spawns a headless child for swatches; keep the real source, not that.
			package.loaded["beast.libs.finder.source.colorscheme_swatches"] = {
				get = function() end,
				ensure = function() end,
			}
			_G.sources = require("beast.libs.finder.source")
			_G.action = require("beast.libs.finder.action")
			_G.cwd = vim.fn.getcwd()
			---Replace `action[key]` with a spy recording its arguments in `_G.spied[key]`.
			_G.spy = function(key)
				_G.spied = _G.spied or {}
				_G.spied[key] = {}
				_G.action[key] = function(...)
					table.insert(_G.spied[key], { ... })
				end
			end
		end)
	end)

	t.after_each(F.close)

	t.describe("buffers", function()
		local b1

		t.before_each(function()
			b1 = child(function()
				local c = vim.api.nvim_create_buf(true, false)
				vim.api.nvim_buf_set_name(c, _G.cwd .. "/zz_buf_clean.lua")
				local d = vim.api.nvim_create_buf(true, false)
				vim.api.nvim_buf_set_name(d, _G.cwd .. "/zz_buf_dirty.lua")
				vim.api.nvim_buf_set_lines(d, 0, -1, false, { "changed" })
				_G.spy("open_file")
				FH.open("buffers")
				return c
			end)
		end)

		t.it("lists the buffers by path relative to cwd", function()
			t.eq(true, F.has_row("zz_buf_clean.lua") and F.has_row("zz_buf_dirty.lua"))
		end)

		t.it("shows the file name, not the buffer number", function()
			t.eq(true, F.has_row("zz_buf_clean.lua") and not F.has_row("[" .. b1 .. "]"))
		end)

		t.it("marks modified buffers with [+]", function()
			local dirty
			for _, row in ipairs(F.rows()) do
				if row:find("zz_buf_dirty", 1, true) then
					dirty = row
				end
			end
			t.eq(true, dirty ~= nil and dirty:find("[+]", 1, true) ~= nil)
		end)

		t.it("opens the buffer's file on Enter", function()
			F.type("clean")
			F.press("<CR>")
			t.eq(
				true,
				child(function()
					return _G.spied.open_file[1][2].file == _G.cwd .. "/zz_buf_clean.lua"
				end)
			)
		end)
	end)

	t.describe("live_grep: matches grouped under one header per file", function()
		t.before_each(function()
			child(function()
				_G.sources.live_grep.get = function(filter, cb)
					local function hit(i, file, lnum, text)
						cb({
							idx = i,
							score = 0,
							text = file .. ":" .. lnum .. ": " .. text,
							file = _G.cwd .. "/" .. file,
							cwd = _G.cwd,
							pos = { lnum, 0 },
							grep_text = text,
							match_text = filter.pattern,
						})
					end
					hit(1, "lua/a.lua", 3, "first x hit")
					hit(2, "lua/a.lua", 9, "second x hit")
					hit(3, "lua/b.lua", 1, "x again")
					cb(nil)
				end
				_G.spy("open_file")
				FH.open("live_grep")
			end)
			F.type("x")
		end)

		t.it("has one header per file", function()
			local headers = count_rows()
			t.eq(2, headers)
		end)

		t.it("has one row per match", function()
			local _, matches = count_rows()
			t.eq(3, matches)
		end)

		t.it("names the file in the header", function()
			t.eq(true, F.has_row("a.lua") and F.has_row("b.lua"))
		end)

		t.it("shows line:col and the text on match rows", function()
			t.eq(true, F.has_row("second x hit"))
		end)

		t.it("opens the selected match on Enter", function()
			F.press("<C-j>")
			F.press("<CR>")
			t.eq(
				9,
				child(function()
					return _G.spied.open_file[1][2].pos[1]
				end)
			)
		end)
	end)

	t.describe("lsp_references", function()
		t.it("groups the matches under one file header when there is more than one result", function()
			child(function()
				_G.sources.lsp_references.get = function(_, cb)
					for i, lnum in ipairs({ 4, 12 }) do
						cb({
							idx = i,
							score = 0,
							text = "lua/c.lua:" .. lnum .. ": use(x)",
							file = _G.cwd .. "/lua/c.lua",
							cwd = _G.cwd,
							pos = { lnum, 2 },
							end_pos = { lnum, 5 },
							grep_text = "use(x)",
						})
					end
					cb(nil)
				end
				FH.finder().open("lsp_references")
				FH.wait(function()
					return FH.window_count() > 0
				end, 2000)
				FH.settle()
			end)
			local _, matches = count_rows()
			t.eq(2, matches)
			t.eq(true, F.has_row("c.lua"))
		end)

		t.describe("with a single result", function()
			t.before_each(function()
				child(function()
					_G.sources.lsp_references.get = function(_, cb)
						cb({
							idx = 1,
							score = 0,
							text = "lua/c.lua:4: use(x)",
							file = _G.cwd .. "/lua/c.lua",
							cwd = _G.cwd,
							pos = { 4, 2 },
							grep_text = "use(x)",
						})
						cb(nil)
					end
					_G.spy("open_file")
					FH.finder().open("lsp_references")
					FH.settle(300)
				end)
			end)

			t.it("does not open the picker", function()
				t.eq(0, F.window_count())
			end)

			t.it("jumps to the only result", function()
				t.eq(
					4,
					child(function()
						return _G.spied.open_file[1][2].pos[1]
					end)
				)
			end)
		end)
	end)

	t.describe("help_tags", function()
		t.before_each(function()
			child(function()
				_G.sources.help_tags.get = function()
					---@diagnostic disable-next-line: redundant-return-value
					return {
						{
							idx = 1,
							score = 0,
							text = "nvim_open_win",
							help_tag = "nvim_open_win",
							file = "/tmp/api.txt",
							is_plugin = false,
						},
					}
				end
				_G.spy("open_file")
				_G.spy("open_help")
				FH.open("help_tags")
			end)
		end)

		t.it("shows the tag", function()
			t.eq(true, F.has_row("nvim_open_win"))
		end)

		t.it("opens help on Enter", function()
			F.press("<CR>")
			t.eq(
				"nvim_open_win",
				child(function()
					return _G.spied.open_help[1][2].help_tag
				end)
			)
		end)

		t.it("opens no file on Enter", function()
			F.press("<CR>")
			t.eq(
				0,
				child(function()
					return #_G.spied.open_file
				end)
			)
		end)
	end)

	t.describe("colorschemes", function()
		t.before_each(function()
			child(function()
				_G.color_gets, _G.applied = 0, 0
				_G.sources.colorschemes.get = function()
					_G.color_gets = _G.color_gets + 1
					---@diagnostic disable-next-line: redundant-return-value
					return {
						{ idx = 1, score = 0, text = "habamax" },
						{ idx = 2, score = 0, text = "quiet" },
					}
				end
				vim.api.nvim_create_autocmd("ColorScheme", {
					group = vim.api.nvim_create_augroup("FinderSourceBehaviorTest", { clear = true }),
					callback = function()
						_G.applied = _G.applied + 1
					end,
				})
				FH.open("colorschemes")
			end)
		end)

		t.it("loads the source once", function()
			t.eq(
				1,
				child(function()
					return _G.color_gets
				end)
			)
		end)

		t.it("reloads the theme list on the swatches event", function()
			t.eq(
				2,
				child(function()
					vim.api.nvim_exec_autocmds("User", { pattern = "BeastFinderSwatchesReady", modeline = false })
					FH.settle()
					return _G.color_gets
				end)
			)
		end)

		t.it("applies the first theme on Enter", function()
			F.press("<CR>")
			t.eq(
				"habamax",
				child(function()
					return vim.g.colors_name
				end)
			)
		end)

		t.it("applies it exactly once", function()
			F.press("<CR>")
			t.eq(
				1,
				child(function()
					return _G.applied
				end)
			)
		end)

		t.it("does not re-apply an already active theme on Enter", function()
			F.press("<CR>")
			child(function()
				FH.open("colorschemes")
			end)
			F.press("<CR>")
			t.eq(
				1,
				child(function()
					return _G.applied
				end)
			)
		end)
	end)

	t.describe("reload events", function()
		t.describe("on a match source", function()
			t.before_each(function()
				child(function()
					_G.gets = 0
					FH.list_source("fake_reload", { "a.lua" }, {
						get = function()
							_G.gets = _G.gets + 1
							return { { idx = 1, score = 0, text = "a.lua", file = "a.lua" } }
						end,
					})
					FH.open("fake_reload")
				end)
			end)

			t.it("loads once", function()
				t.eq(
					1,
					child(function()
						return _G.gets
					end)
				)
			end)

			t.it("reloads on a visibility change", function()
				t.eq(
					2,
					child(function()
						vim.api.nvim_exec_autocmds("User", { pattern = "BeastVisibilityChanged", modeline = false })
						FH.settle()
						return _G.gets
					end)
				)
			end)

			t.it("is not reloaded by the swatches event", function()
				t.eq(
					1,
					child(function()
						vim.api.nvim_exec_autocmds("User", { pattern = "BeastFinderSwatchesReady", modeline = false })
						FH.settle()
						return _G.gets
					end)
				)
			end)
		end)

		t.describe("on a live source", function()
			local r

			t.before_each(function()
				r = child(function()
					_G.runs = {}
					FH.fake_source("fake_reload_live", {
						live = true,
						async = true,
						debounce_ms = 10,
						get = function(filter, cb)
							_G.runs[#_G.runs + 1] = filter.pattern
							cb(nil)
						end,
						cancel = function() end,
					})
					FH.open("fake_reload_live")
					FH.type("ab")
					local before = #_G.runs
					vim.api.nvim_exec_autocmds("User", { pattern = "BeastVisibilityChanged", modeline = false })
					FH.settle()
					return { extra = #_G.runs - before, last = _G.runs[#_G.runs] }
				end)
			end)

			t.it("re-runs its current query", function()
				t.eq(1, r.extra)
			end)

			t.it("with the same text", function()
				t.eq("ab", r.last)
			end)
		end)
	end)

	t.it("opens web address rows in the browser", function()
		child(function()
			_G.opened_urls = {}
			vim.ui.open = function(url)
				_G.opened_urls[#_G.opened_urls + 1] = url
				return {}, nil
			end
			FH.fake_source("fake_url", {
				live = false,
				async = false,
				get = function()
					return { { idx = 1, score = 0, text = "#1 title", url = "https://example.com/1" } }
				end,
			})
			FH.open("fake_url")
		end)
		F.press("<CR>")
		t.eq(
			{ "https://example.com/1" },
			child(function()
				return _G.opened_urls
			end)
		)
	end)

	t.describe("source.preview hook", function()
		t.before_each(function()
			child(function()
				_G.shown = {}
				_G.hook_source = function(name, texts)
					FH.list_source(name, texts, {
						preview = function(_, item)
							_G.shown[#_G.shown + 1] = item and item.text or "nil"
						end,
					})
				end
			end)
		end)

		t.it("is called with the selected item", function()
			child(function()
				_G.hook_source("fake_hook", { "a.lua", "b.lua" })
				FH.open("fake_hook")
				FH.settle(200)
			end)
			t.eq(
				"a.lua",
				child(function()
					return _G.shown[1]
				end)
			)
		end)

		t.it("is called again when the selection moves", function()
			child(function()
				_G.hook_source("fake_hook", { "a.lua", "b.lua" })
				FH.open("fake_hook")
				FH.settle(200)
			end)
			F.press("<C-j>")
			child(function()
				FH.settle(200)
			end)
			t.eq(
				"b.lua",
				child(function()
					return _G.shown[#_G.shown]
				end)
			)
		end)

		t.it("is called with nil when the list is empty", function()
			child(function()
				_G.hook_source("fake_hook_empty", {})
				FH.open("fake_hook_empty")
				FH.settle(200)
			end)
			t.eq(
				"nil",
				child(function()
					return _G.shown[1]
				end)
			)
		end)
	end)
end)
