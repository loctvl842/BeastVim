-- =========================================================================
-- Test: per-source behavior - row format, grouping, Enter action, reload, preview hook
-- =========================================================================
-- Uses the real source modules (names, formats, open behavior) with their data
-- producers replaced by fixed items, and drives the real picker. Characterizes today's
-- name-based behavior so moving it onto the sources
-- (docs/dev-specs/finder-levels-refactor.md, phase 2) cannot change it.
--
-- Run as: nvim --clean --headless -l tests/test-finder-source-behavior.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

local H = dofile("tests/helpers/finder.lua")
local t = H.runner()
local action = require("beast.libs.finder.action")

-- The colorscheme source spawns a headless child for swatches; keep the real source, not that.
package.loaded["beast.libs.finder.source.colorscheme_swatches"] = {
	get = function() end,
	ensure = function() end,
}

local sources = require("beast.libs.finder.source")
local cwd = vim.fn.getcwd()

local function open_file_spy()
	return H.spy(action, "open_file")
end

-- ---------------------------------------------------------------------------
t.section("buffers: [number] name, modified marker, Enter opens the file")
local b1 = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(b1, cwd .. "/zz_buf_clean.lua")
local b2 = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(b2, cwd .. "/zz_buf_dirty.lua")
vim.api.nvim_buf_set_lines(b2, 0, -1, false, { "changed" })
local calls, restore = open_file_spy()
H.open("buffers")
t.ok("lists the buffers by path relative to cwd", H.has_row("zz_buf_clean.lua") and H.has_row("zz_buf_dirty.lua"), vim.inspect(H.rows()))
t.ok("shows the buffer number", H.has_row("[" .. b1 .. "]"))
local dirty
for _, row in ipairs(H.rows()) do
	if row:find("zz_buf_dirty", 1, true) then
		dirty = row
	end
end
t.ok("modified buffers carry [+]", dirty and dirty:find("[+]", 1, true) ~= nil, tostring(dirty))
H.type("clean")
H.press("<CR>")
t.eq("Enter opens the buffer's file", calls[1] and calls[1][2].file, cwd .. "/zz_buf_clean.lua")
restore()
H.close()

-- ---------------------------------------------------------------------------
t.section("live_grep: matches grouped under one header per file")
local grep = sources.live_grep
local real_grep_get = grep.get
grep.get = function(filter, cb)
	local function hit(i, file, lnum, text)
		cb({
			idx = i,
			score = 0,
			text = file .. ":" .. lnum .. ": " .. text,
			file = cwd .. "/" .. file,
			cwd = cwd,
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
calls, restore = open_file_spy()
H.open("live_grep")
H.type("x")
local rows = H.rows()
local headers, matches = 0, 0
for _, row in ipairs(rows) do
	if row:match("^%d+:%d+") then
		matches = matches + 1
	elseif row ~= "" then
		headers = headers + 1
	end
end
t.eq("one header per file", headers, 2)
t.eq("one row per match", matches, 3)
t.ok("header names the file", H.has_row("a.lua") and H.has_row("b.lua"))
t.ok("match rows show line:col and the text", H.has_row("second x hit"))
H.press("<C-j>")
H.press("<CR>")
t.eq("Enter opens the selected match", calls[1] and calls[1][2].pos[1], 9)
restore()
H.close()
grep.get = real_grep_get

-- ---------------------------------------------------------------------------
t.section("lsp_references: same grouping, and the pre-flight opens the picker for >1 result")
local lsp = sources.lsp_references
local real_lsp_get = lsp.get
lsp.get = function(_, cb)
	for i, lnum in ipairs({ 4, 12 }) do
		cb({
			idx = i,
			score = 0,
			text = "lua/c.lua:" .. lnum .. ": use(x)",
			file = cwd .. "/lua/c.lua",
			cwd = cwd,
			pos = { lnum, 2 },
			end_pos = { lnum, 5 },
			grep_text = "use(x)",
		})
	end
	cb(nil)
end
H.finder().open("lsp_references")
H.wait(function()
	return H.window_count() > 0
end, 2000)
H.settle()
local lsp_matches = 0
for _, row in ipairs(H.rows()) do
	if row:match("^%d+:%d+") then
		lsp_matches = lsp_matches + 1
	end
end
t.eq("two matches under one file header", lsp_matches, 2)
t.ok("file header present", H.has_row("c.lua"))
H.close()
lsp.get = real_lsp_get

t.section("lsp_references: a single result jumps without opening the picker")
lsp.get = function(_, cb)
	cb({ idx = 1, score = 0, text = "lua/c.lua:4: use(x)", file = cwd .. "/lua/c.lua", cwd = cwd, pos = { 4, 2 }, grep_text = "use(x)" })
	cb(nil)
end
calls, restore = open_file_spy()
H.finder().open("lsp_references")
H.settle(300)
t.eq("no picker", H.window_count(), 0)
t.eq("jumped to the only result", calls[1] and calls[1][2].pos[1], 4)
restore()
lsp.get = real_lsp_get

-- ---------------------------------------------------------------------------
t.section("help_tags: Enter opens help, not a file")
local help = sources.help_tags
local real_help_get = help.get
help.get = function()
	return { { idx = 1, score = 0, text = "nvim_open_win", help_tag = "nvim_open_win", file = "/tmp/api.txt", is_plugin = false } }
end
local file_calls, r1 = open_file_spy()
local help_calls, r2 = H.spy(action, "open_help")
H.open("help_tags")
t.ok("shows the tag", H.has_row("nvim_open_win"))
H.press("<CR>")
t.eq("Enter opens the help tag", help_calls[1] and help_calls[1][2].help_tag, "nvim_open_win")
t.eq("and no file", #file_calls, 0)
r1()
r2()
H.close()
help.get = real_help_get

-- ---------------------------------------------------------------------------
t.section("colorschemes: Enter applies the theme once, and swatches reload only this source")
local colors = sources.colorschemes
local real_colors_get = colors.get
local color_gets = 0
colors.get = function()
	color_gets = color_gets + 1
	return {
		{ idx = 1, score = 0, text = "habamax" },
		{ idx = 2, score = 0, text = "quiet" },
	}
end
local applied = 0
local group = vim.api.nvim_create_augroup("FinderSourceBehaviorTest", { clear = true })
vim.api.nvim_create_autocmd("ColorScheme", {
	group = group,
	callback = function()
		applied = applied + 1
	end,
})
H.open("colorschemes")
t.eq("source loaded once", color_gets, 1)
vim.api.nvim_exec_autocmds("User", { pattern = "BeastFinderSwatchesReady", modeline = false })
H.settle()
t.eq("the swatches event reloads the theme list", color_gets, 2)
H.press("<CR>")
t.eq("Enter applies the first theme", vim.g.colors_name, "habamax")
t.eq("exactly once", applied, 1)
H.open("colorschemes")
H.press("<CR>")
t.eq("Enter on the already active theme does not re-apply it", applied, 1)
colors.get = real_colors_get
vim.api.nvim_del_augroup_by_id(group)

-- ---------------------------------------------------------------------------
t.section("reload events")
local gets = 0
H.list_source("fake_reload", { "a.lua" }, {
	get = function()
		gets = gets + 1
		return { { idx = 1, score = 0, text = "a.lua", file = "a.lua" } }
	end,
})
H.open("fake_reload")
t.eq("loaded once", gets, 1)
vim.api.nvim_exec_autocmds("User", { pattern = "BeastVisibilityChanged", modeline = false })
H.settle()
t.eq("visibility change reloads any source", gets, 2)
vim.api.nvim_exec_autocmds("User", { pattern = "BeastFinderSwatchesReady", modeline = false })
H.settle()
t.eq("the swatches event does not reload other sources", gets, 2)
H.close()

local runs = {}
H.fake_source("fake_reload_live", {
	live = true,
	async = true,
	debounce_ms = 10,
	get = function(filter, cb)
		runs[#runs + 1] = filter.pattern
		cb(nil)
	end,
	cancel = function() end,
})
H.open("fake_reload_live")
H.type("ab")
local before = #runs
vim.api.nvim_exec_autocmds("User", { pattern = "BeastVisibilityChanged", modeline = false })
H.settle()
t.eq("a live source re-runs its current query", #runs, before + 1)
t.eq("with the same text", runs[#runs], "ab")
H.close()

-- ---------------------------------------------------------------------------
t.section("web address rows open in the browser")
local opened_urls = {}
local orig_open = vim.ui.open
---@diagnostic disable-next-line: duplicate-set-field
vim.ui.open = function(url)
	opened_urls[#opened_urls + 1] = url
	return {}, nil
end
H.fake_source("fake_url", {
	live = false,
	async = false,
	get = function()
		return { { idx = 1, score = 0, text = "#1 title", url = "https://example.com/1" } }
	end,
})
H.open("fake_url")
H.press("<CR>")
t.eq("Enter opens the url", opened_urls, { "https://example.com/1" })
vim.ui.open = orig_open

-- ---------------------------------------------------------------------------
t.section("source.preview hook")
local shown = {}
local function hook_source(name, texts)
	H.list_source(name, texts, {
		preview = function(_, item)
			shown[#shown + 1] = item and item.text or "nil"
		end,
	})
end
hook_source("fake_hook", { "a.lua", "b.lua" })
H.open("fake_hook")
H.settle(200)
t.eq("called with the selected item", shown[1], "a.lua")
H.press("<C-j>")
H.settle(200)
t.eq("and again when the selection moves", shown[#shown], "b.lua")
H.close()
shown = {}
hook_source("fake_hook_empty", {})
H.open("fake_hook_empty")
H.settle(200)
t.eq("called with nil when the list is empty", shown[1], "nil")
H.close()

t.done()
