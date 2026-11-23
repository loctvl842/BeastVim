local F = require("test.libs.finder.helpers.finder")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Every finder source declares its own behavior (docs/dev-specs/finder-levels-refactor.md, phase 2):
-- rows, grouping, Enter, reload events and preview highlight live on the source, so no other module
-- needs to know which source it is dealing with.

local NAMES = {
	"buffers",
	"colorschemes",
	"files",
	"gh_issue",
	"gh_pr",
	"gl_issue",
	"gl_mr",
	"help_tags",
	"live_grep",
	"lsp_declarations",
	"lsp_definitions",
	"lsp_implementations",
	"lsp_references",
}
local GROUPED = {
	live_grep = true,
	lsp_definitions = true,
	lsp_references = true,
	lsp_declarations = true,
	lsp_implementations = true,
}
local PREVIEWS = {
	live_grep = "match",
	lsp_definitions = "range",
	lsp_references = "range",
	lsp_declarations = "range",
	lsp_implementations = "range",
}

t.describe("finder source contract", function()
	t.before_each(function()
		F.setup()
		n.exec_lua(function()
			-- Not the swatch worker (it spawns a headless child).
			package.loaded["beast.libs.finder.source.colorscheme_swatches"] = { get = function() end, ensure = function() end }
			_G.sources = require("beast.libs.finder.source")
			_G.action = require("beast.libs.finder.action")
			local cwd = vim.fn.getcwd()
			local file_item = { idx = 1, score = 0, text = "lua/a.lua", file = cwd .. "/lua/a.lua", cwd = cwd }
			local grep_item = vim.tbl_extend("force", file_item, { pos = { 3, 1 }, grep_text = "hit", match_text = "hit", text = "lua/a.lua:3: hit" })
			local gh_item = {
				idx = 1,
				score = 1,
				text = "#1 t",
				kind = "pr",
				state = "open",
				number = 1,
				title = "t",
				author = "me",
				labels = {},
				url = "https://github.com/o/n/pull/1",
			}
			_G.samples = {
				files = file_item,
				buffers = vim.tbl_extend("force", file_item, { buf = 1 }),
				live_grep = grep_item,
				help_tags = { idx = 1, score = 0, text = "tag", help_tag = "tag", file = "/tmp/x.txt" },
				colorschemes = { idx = 1, score = 0, text = "habamax" },
				lsp_definitions = grep_item,
				lsp_references = grep_item,
				lsp_declarations = grep_item,
				lsp_implementations = grep_item,
				gh_pr = gh_item,
				gh_issue = vim.tbl_extend("force", gh_item, { kind = "issue" }),
				gl_mr = vim.tbl_extend("force", gh_item, {
					provider = "gitlab",
					ref = "!1",
					url = "https://gitlab.com/o/n/-/merge_requests/1",
				}),
				gl_issue = vim.tbl_extend("force", gh_item, {
					provider = "gitlab",
					kind = "issue",
					ref = "#1",
					url = "https://gitlab.com/o/n/-/issues/1",
				}),
			}
		end)
	end)

	t.after_each(F.close)

	---One source's contract, reduced to plain data.
	---@param name string
	---@return table
	local function inspect(name)
		return n.exec_lua(function(name)
			local source = _G.sources[name]
			local sample = _G.samples[name]
			local row = source.format(sample, 60)
			local header_ok
			if source.header then
				local header = source.header(sample, 60)
				header_ok = type(header) == "table" and #header > 0
			end
			return {
				name = source.name,
				format = type(source.format),
				open = type(source.open),
				reload_on = type(source.reload_on),
				group_is_file = source.group(sample) == sample.file,
				row_ok = type(row) == "table" and #row > 0 and (row[1].text ~= nil or row[1].chunks ~= nil),
				has_header = source.header ~= nil,
				header_ok = header_ok or false,
				preview_highlight = source.preview_highlight or false,
			}
		end, name)
	end

	t.describe("every registered source is complete", function()
		for _, name in ipairs(NAMES) do
			t.describe(name, function()
				local r

				t.before_each(function()
					r = inspect(name)
				end)

				t.it("has its registry key as name", function()
					t.eq(name, r.name)
				end)

				t.it("has a row formatter", function()
					t.eq("function", r.format)
				end)

				t.it("has an open action", function()
					t.eq("function", r.open)
				end)

				t.it("declares its reload events", function()
					t.eq("table", r.reload_on)
				end)

				t.it("groups by file unless it says otherwise", function()
					t.eq(true, r.group_is_file)
				end)

				t.it("returns highlight chunks from the formatter", function()
					t.eq(true, r.row_ok)
				end)

				t.it("has a grouped header only for grep and LSP", function()
					t.eq(GROUPED[name] == true, r.has_header)
				end)

				if GROUPED[name] then
					t.it("returns chunks from the header", function()
						t.eq(true, r.header_ok)
					end)
				end

				t.it("declares its preview highlight", function()
					t.eq(PREVIEWS[name] or false, r.preview_highlight)
				end)
			end)
		end
	end)

	t.describe("defaults come from the registry", function()
		t.it("reloads on the visibility change by default", function()
			t.eq(
				{ "BeastVisibilityChanged" },
				n.exec_lua(function()
					return _G.sources.files.reload_on
				end)
			)
		end)

		t.it("reloads colorschemes when swatches are ready", function()
			t.eq(
				{ "BeastFinderSwatchesReady" },
				n.exec_lua(function()
					return _G.sources.colorschemes.reload_on
				end)
			)
		end)

		t.it("opens with the shared default", function()
			t.eq(
				true,
				n.exec_lua(function()
					return _G.sources.files.open == _G.action.open_default
				end)
			)
		end)

		t.it("gives help_tags its own open", function()
			t.eq(
				true,
				n.exec_lua(function()
					return _G.sources.help_tags.open ~= _G.action.open_default
				end)
			)
		end)

		t.it("gives colorschemes its own open", function()
			t.eq(
				true,
				n.exec_lua(function()
					return _G.sources.colorschemes.open ~= _G.action.open_default
				end)
			)
		end)
	end)

	t.describe("default open: url, else file", function()
		local r

		t.before_each(function()
			r = n.exec_lua(function()
				local state = { main_win = require("beast.libs.view").win.find_normal() or vim.api.nvim_get_current_win() }
				local opened_urls, file_calls = {}, {}
				vim.ui.open = function(url)
					opened_urls[#opened_urls + 1] = url
					return {}, nil
				end
				_G.action.open_file = function(...)
					file_calls[#file_calls + 1] = { ... }
				end
				_G.sources.files.open(state, { url = "https://example.com", file = "/x" })
				local after_url = #file_calls
				_G.sources.files.open(state, { file = "/x" })
				return {
					urls = opened_urls,
					files_after_url = after_url,
					file = file_calls[1] and file_calls[1][2].file,
					in_main_win = file_calls[1] and file_calls[1][1] == state.main_win,
				}
			end)
		end)

		t.it("opens the browser for an item with a url", function()
			t.eq({ "https://example.com" }, r.urls)
		end)

		t.it("does not open the file then", function()
			t.eq(0, r.files_after_url)
		end)

		t.it("opens the file for an item with only a file", function()
			t.eq("/x", r.file)
		end)

		t.it("opens it in the picker's main window", function()
			t.eq(true, r.in_main_win)
		end)
	end)

	t.describe("action.open asks the source", function()
		t.before_each(function()
			n.exec_lua(function()
				FH.list_source("fake_open", { "a.lua" }, {
					open = function(s, item)
						_G.seen = { text = item.text, has_main_win = s.main_win ~= nil }
					end,
				})
				FH.open("fake_open")
			end)
			F.press("<CR>")
		end)

		t.it("runs the source's open with the item on Enter", function()
			t.eq(
				"a.lua",
				n.exec_lua(function()
					return _G.seen and _G.seen.text
				end)
			)
		end)

		t.it("passes the picker as the first argument", function()
			t.eq(
				true,
				n.exec_lua(function()
					return _G.seen and _G.seen.has_main_win
				end)
			)
		end)
	end)

	t.describe("rows are grouped by source.group", function()
		t.it("shows one header per group, not per file", function()
			n.exec_lua(function()
				FH.fake_source("fake_group", {
					live = false,
					async = false,
					get = function()
						return {
							{ idx = 1, score = 0, text = "a1", file = "same.lua", g = "one" },
							{ idx = 2, score = 0, text = "a2", file = "same.lua", g = "one" },
							{ idx = 3, score = 0, text = "b1", file = "same.lua", g = "two" },
						}
					end,
					group = function(item)
						return item.g
					end,
					header = function(item)
						return { { text = "HEADER " .. item.g, hl = "BeastFinderListFile" } }
					end,
					format = function(item)
						return { { text = item.text, hl = "BeastFinderListFile" } }
					end,
				})
				FH.open("fake_group")
			end)
			t.eq({ "HEADER one", "a1", "a2", "HEADER two", "b1" }, F.rows())
		end)

		t.it("groups by file without a group function", function()
			n.exec_lua(function()
				FH.fake_source("fake_group_default", {
					live = false,
					async = false,
					get = function()
						return {
							{ idx = 1, score = 0, text = "a1", file = "f1.lua" },
							{ idx = 2, score = 0, text = "a2", file = "f1.lua" },
							{ idx = 3, score = 0, text = "b1", file = "f2.lua" },
						}
					end,
					header = function(item)
						return { { text = "HEADER " .. item.file, hl = "BeastFinderListFile" } }
					end,
					format = function(item)
						return { { text = item.text, hl = "BeastFinderListFile" } }
					end,
				})
				FH.open("fake_group_default")
			end)
			t.eq({ "HEADER f1.lua", "a1", "a2", "HEADER f2.lua", "b1" }, F.rows())
		end)
	end)

	t.it("has no module outside source/init.lua dispatching on a source name", function()
		t.eq(
			{},
			n.exec_lua(function()
				local offenders = {}
				for _, path in ipairs(vim.fn.globpath("lua/beast/libs/finder", "**/*.lua", false, true)) do
					-- chain.lua is the other place that knows source names: chains.lua is the one map of what leads where.
					if not path:find("source/init.lua", 1, true) and not path:find("finder/chain.lua", 1, true) then
						for lnum, line in ipairs(vim.fn.readfile(path)) do
							local code = line:gsub("%-%-.*$", "")
							if
								code:find("source.name", 1, true)
								or code:find(".name ==", 1, true)
								or code:find(".name:match", 1, true)
								or code:find("format[", 1, true)
							then
								offenders[#offenders + 1] = path .. ":" .. lnum .. ": " .. vim.trim(line)
							end
						end
					end
				end
				return offenders
			end)
		)
	end)
end)
