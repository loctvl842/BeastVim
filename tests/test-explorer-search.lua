-- =========================================================================
-- Test: explorer search mode (SearchTree, mode state, prompt, lifecycle)
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-explorer-search.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

_G.Theme = {
	get = function()
		return setmetatable({}, {
			__index = function()
				return "#ffffff"
			end,
		})
	end,
	refresh = function() end,
}
_G.Util = require("beast.util")
_G.Toast = function(...) end
_G.Icon = require("beast.icon")
_G.View = require("beast.libs.view")
package.loaded["nvim-web-devicons"] = {
	get_icon = function()
		return "󰈙", "DevIconDefault"
	end,
}

local passed, failed = 0, 0
local degraded = _G.arg and _G.arg[1] == "degraded"

local function assert_test(name, cond, msg)
	if cond then
		passed = passed + 1
		io.write("  PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL: " .. name .. " - " .. (msg or "assertion failed") .. "\n")
	end
end

--- True when `buf` has a buffer-local normal-mode mapping for `lhs`.
local function has_map(buf, lhs)
	local raw = vim.api.nvim_replace_termcodes(lhs, true, true, true)
	for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
		if m.lhsraw == raw then
			return true
		end
	end
	return false
end

local function write(path)
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	vim.fn.writefile({ "x" }, path)
end

-- =========================================================================
-- Without the finder (child run with `degraded`): / and ? keep their Neovim meaning
-- =========================================================================
if degraded then
	package.loaded["beast.libs.finder.search"] = {
		available = function()
			return false
		end,
	}
	local d_root = vim.fn.resolve(vim.fn.tempname())
	write(d_root .. "/a.lua")
	local d_explorer = require("beast.libs.explorer")
	d_explorer.setup({})
	d_explorer.open(d_root)
	local buf = require("beast.libs.explorer.state").view.buf
	assert_test("degraded: / not mapped", not has_map(buf, "/"))
	assert_test("degraded: ? not mapped", not has_map(buf, "?"))
	assert_test("degraded: <Esc><Esc> not mapped", not has_map(buf, "<Esc><Esc>"))
	assert_test("degraded: other keys still mapped", has_map(buf, "<CR>"))
	vim.fn.delete(d_root, "rf")
	io.write(string.format("\n%d passed, %d failed\n", passed, failed))
	os.exit(failed == 0 and 0 or 1)
end

-- =========================================================================
-- SearchTree (pure)
-- =========================================================================
io.write("\n--- SearchTree.from_matches ---\n")
local SearchTree = require("beast.libs.explorer.search.tree")
local Tree = require("beast.libs.explorer.tree")
local st = SearchTree.from_matches("/r", {
	{ text = "lua/beast/libs/explorer/init.lua", positions = { 25, 26, 27, 28, 29, 30, 31, 32 } },
	{ text = "lua/beast/init.lua", positions = { 11, 12, 13, 14, 15, 16, 17, 18 } },
	{ text = "README.md" },
}, true)
local names = {}
for _, n in ipairs(st:flat({ show_hidden = true })) do
	names[#names + 1] = string.rep(" ", n.depth) .. n.name .. (n.last and "$" or "")
end
assert_test(
	"tree order: dirs first, then files, depth-indented",
	vim.deep_equal(names, { "lua", " beast", "  libs", "   explorer$", "    init.lua$", "  init.lua$", "README.md$" })
		or vim.deep_equal(names, { "lua", " beast$", "  libs", "   explorer$", "    init.lua$", "  init.lua$", "README.md$" }),
	vim.inspect(names)
)
assert_test("is a Tree subclass", getmetatable(st) == SearchTree and SearchTree.flat == Tree.flat)
assert_test("count and capped kept", st.count == 3 and st.capped == true)
assert_test(
	"matched letters mapped to the name (0-based)",
	st.positions["/r/lua/beast/init.lua"] and st.positions["/r/lua/beast/init.lua"][0] and st.positions["/r/lua/beast/init.lua"][7]
)

-- =========================================================================
-- Prompt key loop (typed keys are queued, then read by getcharstr)
-- =========================================================================
io.write("\n--- search.prompt.ask ---\n")
local prompt = require("beast.libs.explorer.search.prompt")
local function typed(keys, default)
	local changes = {}
	vim.api.nvim_feedkeys(vim.keycode(keys), "t", false)
	local text = prompt.ask(default or "", function(t)
		changes[#changes + 1] = t
	end)
	return text, changes
end
local text, changes = typed("abc<BS>d<CR>")
assert_test("characters and <BS> edit the text", text == "abd", tostring(text))
assert_test("on_change fires per edit", #changes == 5 and changes[5] == "abd", vim.inspect(changes))
assert_test("<C-w> deletes a word", typed("foo bar<C-w><CR>") == "foo", "")
assert_test("<C-u> clears", typed("foo<C-u>x<CR>") == "x", "")
assert_test("default text is kept and editable", typed("c<CR>", "ab") == "abc", "")
assert_test("<Esc> cancels", typed("abc<Esc>") == nil, "")

-- =========================================================================
-- Lifecycle against a real explorer window
-- =========================================================================
local root = vim.fn.resolve(vim.fn.tempname())
write(root .. "/lua/beast/init.lua")
write(root .. "/lua/beast/libs/explorer/init.lua")
write(root .. "/lua/beast/libs/finder/init.lua")
write(root .. "/README.md")

local explorer = require("beast.libs.explorer")
local search = require("beast.libs.explorer.search")
local state = require("beast.libs.explorer.state")
local ui = require("beast.libs.explorer.ui")

explorer.setup({})
explorer.open(root)
local view_buf, view_win = state.view.buf, state.view.win
local real_tree = state.tree

local function buf_lines()
	return vim.api.nvim_buf_get_lines(view_buf, 0, -1, false)
end
---@return Beast.Explorer.SearchTree
local function search_tree()
	return state.tree --[[@as Beast.Explorer.SearchTree]]
end

local function wait_count(n)
	vim.wait(3000, function()
		return state.mode == "search" and search_tree().count == n and not state.mode_state.loading
	end, 10)
end
local function row_of(name)
	for i, l in ipairs(buf_lines()) do
		if l:find(name, 1, true) then
			return i
		end
	end
end

io.write("\n--- start() ---\n")
assert_test("normal title has no mode label", vim.trim(buf_lines()[1]) == vim.fn.fnamemodify(root, ":t"):upper(), buf_lines()[1])
assert_test("normal mode by default", state.mode == "normal" and state.mode_state == nil)
search.start()
assert_test("mode is search", state.mode == "search" and search.is_active())
assert_test("state.tree is a SearchTree", getmetatable(state.tree) == SearchTree and state.tree ~= real_tree)
assert_test("buffer and window are the explorer's own", state.view.buf == view_buf and vim.api.nvim_win_get_buf(view_win) == view_buf)
assert_test(
	"starts empty: only the root title",
	#buf_lines() == 1 and vim.trim(buf_lines()[1]) == vim.fn.fnamemodify(root, ":t"):upper() .. " (Search)",
	vim.inspect(buf_lines())
)

io.write("\n--- set_query() ---\n")
search.set_query("in.lua")
wait_count(3)
local lines = buf_lines()
assert_test("title shown once typing ended", vim.trim(lines[1]) == vim.fn.fnamemodify(root, ":t"):upper() .. " (Search)", lines[1])
assert_test("three files plus their folders", #lines == 1 + 3 + 5, vim.inspect(lines))
assert_test("cursor on first file row", vim.api.nvim_win_get_cursor(view_win)[1] > 1)
assert_test("real tree untouched", not (real_tree.nodes[root .. "/lua"] and real_tree.nodes[root .. "/lua"].open))
state.mode_state.prompting = true
ui.flush()
assert_test("query line while typing", vim.trim(buf_lines()[1]) == "/ in.lua▏", buf_lines()[1])
assert_test("no trailing space on the query line", not buf_lines()[1]:match("%s$"))
state.mode_state.prompting = false
ui.flush()
local marks = vim.api.nvim_buf_get_extmarks(view_buf, state.view.ns, 0, -1, { details = true })
local matched = 0
for _, m in ipairs(marks) do
	if m[4].hl_group == "BeastExplorerSearchMatch" then
		matched = matched + 1
	end
end
assert_test("matched letters highlighted", matched > 0, tostring(matched))

search.set_query("zzzz")
vim.wait(3000, function()
	return search_tree().count == 0 and not state.mode_state.loading and state.mode_state.query == "zzzz"
end, 10)
assert_test("empty-result message", (buf_lines()[2] or ""):find('No files match "zzzz"', 1, true) ~= nil, vim.inspect(buf_lines()))
search.set_query("")
assert_test("empty query clears the results", #buf_lines() == 1)

io.write("\n--- normal-mode features on result rows ---\n")
search.set_query("in.lua")
wait_count(3)
local lua_row = row_of("lua")
vim.api.nvim_win_set_cursor(view_win, { lua_row, 0 })
local before = #buf_lines()
require("beast.libs.explorer.actions.open").run()
assert_test("<CR> on a folder closes it", #buf_lines() < before, #buf_lines() .. " vs " .. before)
require("beast.libs.explorer.actions.open").run()
assert_test("<CR> again opens it (children collapsed, like the normal tree)", row_of("beast") ~= nil and #buf_lines() < before)
state.tree:open(root .. "/lua/beast/init.lua")
state.tree:open(root .. "/lua/beast/libs/explorer/init.lua")
ui.render()
before = #buf_lines()
-- delete a result file: the row goes away, nothing else comes back
local victim = root .. "/lua/beast/init.lua"
vim.fn.delete(victim)
state.tree:refresh(root .. "/lua/beast")
ui.render()
assert_test("deleted file leaves the results", row_of("beast/init.lua") == nil and #buf_lines() == before - 1, vim.inspect(buf_lines()))
assert_test("other files in that folder did not come back", state.tree.nodes[root .. "/lua/beast/libs"] ~= nil)
write(victim)
-- create: a new file opened through the tree shows up
write(root .. "/lua/beast/new.lua")
state.tree:refresh(root .. "/lua/beast")
state.tree:open(root .. "/lua/beast/new.lua")
ui.render()
assert_test("created file appears", row_of("new.lua") ~= nil)

io.write("\n--- exit() reveals the selected file ---\n")
search.set_query("finder")
wait_count(1)
local selected = state.current_node({ show_hidden = true })
assert_test("cursor on finder/init.lua", selected and selected.path == root .. "/lua/beast/libs/finder/init.lua", selected and selected.path)
search.exit()
assert_test("mode is normal again", state.mode == "normal" and state.mode_state == nil and not search.is_active())
assert_test("the real tree is back", state.tree == real_tree)
assert_test(
	"selected file's folders are open",
	real_tree.nodes[root .. "/lua/beast/libs/finder"] and real_tree.nodes[root .. "/lua/beast/libs/finder"].open
)
local cur = state.current_node({ show_hidden = true })
assert_test("explorer cursor on init.lua", cur and cur.path == root .. "/lua/beast/libs/finder/init.lua", cur and cur.path)

io.write("\n--- leaving the explorer window ends search mode ---\n")
local other = vim.tbl_filter(function(w)
	return w ~= view_win
end, vim.api.nvim_tabpage_list_wins(0))[1]
vim.api.nvim_win_call(other, function()
	vim.cmd("edit " .. vim.fn.fnameescape(root .. "/README.md"))
end)
search.start()
search.set_query("finder")
wait_count(1)
vim.api.nvim_set_current_win(other)
vim.wait(1000, function()
	return not search.is_active()
end, 10)
assert_test("search mode ended after focus left", not search.is_active() and state.tree == real_tree)
assert_test("cursor is visible in the other window", not vim.o.guicursor:find("BeastExplorerCursor", 1, true), vim.o.guicursor)
assert_test("focus stayed in the other window", vim.api.nvim_get_current_win() == other)
local focus = vim.api.nvim_buf_get_lines(view_buf, vim.api.nvim_win_get_cursor(view_win)[1] - 1, vim.api.nvim_win_get_cursor(view_win)[1], false)[1]
assert_test("explorer cursor on the file now open", focus:find("README.md", 1, true) ~= nil, focus)
vim.api.nvim_set_current_win(view_win)

io.write("\n--- root changes and stop ---\n")
search.start()
search.set_query("finder")
wait_count(1)
vim.api.nvim_win_set_cursor(view_win, { row_of("finder"), 0 })
require("beast.libs.explorer.actions.set_root").run()
assert_test("set_root ends search first", state.mode == "normal" and state.tree.root.path == root .. "/lua/beast/libs/finder")
require("beast.libs.explorer.actions.navigate_up").run()
assert_test("navigate_up back to the parent", state.tree.root.path == root .. "/lua/beast/libs")
state.tree = real_tree
ui.render()
search.stop()
search.stop()
assert_test("stop twice is safe", not search.is_active())
search.start()
explorer.close()
assert_test("closing the explorer ends search mode", not search.is_active())

io.write("\n--- keys: mapped when the finder is available ---\n")
explorer.open(root)
for _, lhs in ipairs({ "/", "?", "<Esc><Esc>" }) do
	assert_test(lhs .. " mapped in the explorer", has_map(state.view.buf, lhs))
end

io.write("\n--- graceful degradation (finder unavailable, child nvim) ---\n")
local child = vim.system({ "nvim", "--clean", "--headless", "-l", "tests/test-explorer-search.lua", "degraded" }, { text = true }):wait()
io.write(child.stdout .. child.stderr)
assert_test("degraded run passes", child.code == 0, "exit " .. child.code)

vim.fn.delete(root, "rf")
io.write(string.format("\n%d passed, %d failed\n", passed, failed))
os.exit(failed == 0 and 0 or 1)
