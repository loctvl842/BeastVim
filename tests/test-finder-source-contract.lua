-- =========================================================================
-- Test: every finder source declares its own behavior (docs/dev-specs/finder-levels-refactor.md, phase 2)
-- =========================================================================
-- Rows, grouping, Enter, reload events and preview highlight live on the source, so no other
-- module needs to know which source it is dealing with.
--
-- Run as: nvim --clean --headless -l tests/test-finder-source-contract.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

local H = dofile("tests/helpers/finder.lua")
local t = H.runner()
local action = require("beast.libs.finder.action")
local sources = require("beast.libs.finder.source")

-- Not the swatch worker (it spawns a headless child).
package.loaded["beast.libs.finder.source.colorscheme_swatches"] = { get = function() end, ensure = function() end }

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
local samples = {
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
}
local grouped = { live_grep = true, lsp_definitions = true, lsp_references = true, lsp_declarations = true, lsp_implementations = true }
local previews =
	{ live_grep = "match", lsp_definitions = "range", lsp_references = "range", lsp_declarations = "range", lsp_implementations = "range" }

local names = vim.tbl_keys(samples)
table.sort(names)

t.section("every registered source is complete")
for _, name in ipairs(names) do
	local source = sources[name]
	t.eq(name .. ": name is its registry key", source.name, name)
	t.eq(name .. ": has a row formatter", type(source.format), "function")
	t.eq(name .. ": has an open action", type(source.open), "function")
	t.eq(name .. ": declares its reload events", type(source.reload_on), "table")
	t.eq(name .. ": groups by file unless it says otherwise", source.group(samples[name]), samples[name].file)
	local row = source.format(samples[name], 60)
	t.ok(name .. ": formatter returns highlight chunks", type(row) == "table" and #row > 0 and (row[1].text ~= nil or row[1].chunks ~= nil))
	t.eq(name .. ": grouped header only for grep and LSP", source.header ~= nil, grouped[name] == true)
	if source.header then
		local header = source.header(samples[name], 60)
		t.ok(name .. ": header returns chunks", type(header) == "table" and #header > 0)
	end
	t.eq(name .. ": preview highlight", source.preview_highlight, previews[name])
end

t.section("defaults come from the registry")
t.eq("default reload event is the visibility change", sources.files.reload_on, { "BeastVisibilityChanged" })
t.eq("colorschemes reload when swatches are ready", sources.colorschemes.reload_on, { "BeastFinderSwatchesReady" })
t.eq("default open is the shared default", sources.files.open, action.open_default)
t.ok("help_tags has its own open", sources.help_tags.open ~= action.open_default)
t.ok("colorschemes has its own open", sources.colorschemes.open ~= action.open_default)

t.section("default open: url, else file")
local state = { main_win = H.main_win() }
local opened_urls = {}
local orig_open = vim.ui.open
---@diagnostic disable-next-line: duplicate-set-field
vim.ui.open = function(url)
	opened_urls[#opened_urls + 1] = url
	return {}, nil
end
local file_calls, restore = H.spy(action, "open_file")
sources.files.open(state, { url = "https://example.com", file = "/x" })
t.eq("an item with a url opens the browser", opened_urls, { "https://example.com" })
t.eq("and not the file", #file_calls, 0)
sources.files.open(state, { file = "/x" })
t.eq("an item with only a file opens the file", file_calls[1] and file_calls[1][2].file, "/x")
t.eq("in the picker's main window", file_calls[1] and file_calls[1][1], state.main_win)
restore()
vim.ui.open = orig_open

t.section("action.open asks the source")
local seen
H.list_source("fake_open", { "a.lua" }, {
	open = function(s, item)
		seen = { s = s, item = item }
	end,
})
H.open("fake_open")
H.press("<CR>")
t.eq("Enter runs the source's open with the picker and the item", seen and seen.item.text, "a.lua")
t.ok("the first argument is the picker", seen and seen.s.main_win ~= nil)

t.section("rows are grouped by source.group")
H.fake_source("fake_group", {
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
H.open("fake_group")
local rows = H.rows()
t.eq("one header per group, not per file", rows, { "HEADER one", "a1", "a2", "HEADER two", "b1" })
H.close()
H.fake_source("fake_group_default", {
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
H.open("fake_group_default")
t.eq("without group, rows group by file", H.rows(), { "HEADER f1.lua", "a1", "a2", "HEADER f2.lua", "b1" })
H.close()

t.section("no module outside source/init.lua dispatches on a source name")
local offenders = {}
for _, path in ipairs(vim.fn.globpath("lua/beast/libs/finder", "**/*.lua", false, true)) do
	if not path:find("source/init.lua", 1, true) then
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
t.eq("no name dispatch", offenders, {})

t.done()
