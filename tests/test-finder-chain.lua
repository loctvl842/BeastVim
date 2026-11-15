-- =========================================================================
-- Test: chains - the closed edge map, the keys, the hint line and scoped grep
-- (docs/dev-specs/finder-continuous.md, Phase 2)
--
-- Run as: nvim --clean --headless -l tests/test-finder-chain.lua
-- Needs fd or rg, and rg, on PATH.
-- =========================================================================
local H = dofile("tests/helpers/finder.lua")
H.boot()
local t = H.runner()
local chain = require("beast.libs.finder.chain")

t.section("closed edge map")
t.eq("files -> live_grep exists", chain.edge("files", "live_grep").to, "live_grep")
for _, pair in ipairs({
	{ "live_grep", "files" },
	{ "live_grep", "gh_pr" },
	{ "colorschemes", "files" },
	{ "files", "buffers" },
}) do
	local ok, err = pcall(chain.edge, pair[1], pair[2])
	t.ok(("%s -> %s raises"):format(pair[1], pair[2]), not ok and tostring(err):find(pair[1] .. " -> " .. pair[2], 1, true), tostring(err))
end
local sources = {}
for _, path in ipairs(vim.fn.globpath("lua/beast/libs/finder/source", "*.lua", false, true)) do
	local name = vim.fn.fnamemodify(path, ":t:r")
	if name ~= "init" then
		sources[#sources + 1] = name
	end
end
for _, dir_name in ipairs({ "live_grep" }) do
	sources[#sources + 1] = dir_name
end
local valid = {
	["files>live_grep"] = true,
	["buffers>live_grep"] = true,
	["help_tags>live_grep"] = true,
	["gh_pr>gh_pr_files"] = true,
	["gh_pr>gh_commits"] = true,
	["gh_commits>live_grep"] = true,
	["gh_pr_files>live_grep"] = true,
	["gh_issue>gh_issue_grep"] = true,
}
local wrong = {}
for _, from in ipairs(sources) do
	for _, to in ipairs(sources) do
		local ok = pcall(chain.edge, from, to)
		if ok ~= (valid[from .. ">" .. to] == true) then
			wrong[#wrong + 1] = from .. " -> " .. to
		end
	end
end
t.ok("sources were found", #sources >= 12, vim.inspect(sources))
t.eq("exactly the built-in edges exist, every other pair raises", wrong, {})
t.eq("finder.chains() lists the enabled edges", #require("beast.libs.finder").chains(), #require("beast.libs.finder.chains"))

t.section("files -> grep")
local dir = vim.fn.resolve(vim.fn.tempname())
vim.fn.mkdir(dir .. "/nested", "p")
local function write(name, line)
	vim.fn.writefile({ line }, dir .. "/" .. name)
end
write("a.lua", "hello alpha")
write("b.lua", "hello beta")
write("nested/d.lua", "hello delta")
write("c.txt", "hello text")
vim.cmd("cd " .. vim.fn.fnameescape(dir))

H.open("files", { cwd = dir })
H.settle(500)
H.type("lua")
t.eq("count shows the matches over the total", H.count(), "3/4")
t.ok("hint offers the grep", H.hint():find("<C-g> grep 3 files", 1, true) ~= nil, H.hint())
t.ok("no way back at the first level", H.hint():find("<BS>", 1, true) == nil, H.hint())

H.press("<C-g>")
H.settle(200)
t.eq("title says what was scoped", H.title(), "3 Files › Live Grep")
t.eq("the prompt starts empty", H.prompt(), "")
t.ok("the list says what to type", H.has_row("type to search inside the 3 files"), vim.inspect(H.rows()))
t.ok("hint offers the way back", H.hint():find("<BS> back to Files", 1, true) ~= nil, H.hint())

H.type("hello", 600)
t.ok("a.lua found", H.has_row("a.lua"), vim.inspect(H.rows()))
t.ok("nested/d.lua found", H.has_row("d.lua"), vim.inspect(H.rows()))
t.ok("c.txt is not searched", not H.has_row("c.txt"), vim.inspect(H.rows()))

H.type("")
H.press("<BS>")
H.settle(200)
t.eq("empty <BS> returns to the files, prompt as left", H.prompt(), "lua")
t.eq("count is back", H.count(), "3/4")
t.eq("title is back", H.title(), "Files")

H.press("<C-g>")
H.settle(200)
H.press("<C-o>")
H.settle(200)
t.eq("<C-o> also comes back", H.title(), "Files")

H.press("<C-g>")
H.settle(200)
H.type("h", 300)
H.press("<BS>")
t.eq("<BS> with text is a normal backspace (stays in grep)", H.title(), "3 Files › Live Grep")
H.close()
t.eq("no hint line is left behind", H.hint(), "")

t.section("buffers -> grep")
local nb = {}
for _, name in ipairs({ "a.lua", "c.txt" }) do
	vim.cmd("edit " .. vim.fn.fnameescape(dir .. "/" .. name))
	nb[#nb + 1] = vim.api.nvim_get_current_buf()
end
vim.cmd("enew") -- a nameless buffer
H.open("buffers", { cwd = dir })
H.settle(300)
H.type("lua")
H.press("<C-g>")
H.settle(200)
t.eq("buffers: title names the scoped buffers", H.title(), "1 Buffers › Live Grep")
t.ok("buffers: hint names the way back", H.hint():find("<BS> back to Buffers", 1, true) ~= nil, H.hint())
H.type("hello", 600)
t.ok("buffers: a.lua found", H.has_row("a.lua"), vim.inspect(H.rows()))
t.ok("buffers: b.lua (not open) is not searched", not H.has_row("b.lua"), vim.inspect(H.rows()))
H.close()

t.section("help -> grep")
H.open("help_tags")
H.settle(500)
H.type("nvim_buf_set_lines")
H.press("<C-g>")
H.settle(300)
t.ok("help: title counts help files", H.title():match("^%d+ Help Files › Live Grep$") ~= nil, H.title())
H.type("nvim_buf_set_lines", 800)
t.ok("help: a hit inside a help page", H.has_row("api.txt"), vim.inspect(H.rows()))
H.press("<BS>")
H.type("")
H.press("<BS>")
H.settle(200)
t.eq("help: back to the tags", H.title(), "Help tags")
H.close()

t.section("hint comes back after it was hidden")
H.open("files", { cwd = dir })
H.settle(500)
H.type("lua")
t.ok("hint shown", H.hint() ~= "", H.hint())
H.type("zzzzqq")
t.eq("hint hidden when nothing matches", H.hint(), "")
H.type("lua")
t.ok("hint is back", H.hint():find("<C-g> grep", 1, true) ~= nil, H.hint())

t.section("drill before the typed text was searched")
local toasts0 = #(rawget(_G, "__toasts") or {})
local seen = {}
_G.Toast = function(msg)
	seen[#seen + 1] = msg
end
local input = H.panes().input
local prefix = require("beast.libs.finder.config").prompt_prefix
vim.api.nvim_buf_set_lines(input.buf, 0, 1, false, { prefix .. "b" }) -- typed, debounce not fired
H.press("<C-g>")
t.eq("refused while the text is not searched yet", { seen[#seen], H.title() }, { "Still searching - try again in a moment", "Files" })
H.close()

t.section("a parked level reloads when hidden files are toggled")
H.open("files", { cwd = dir })
H.settle(500)
H.press("<C-g>")
H.settle(200)
local before = #H.rows()
vim.api.nvim_exec_autocmds("User", { pattern = "BeastVisibilityChanged" })
H.settle(300)
local session = require("beast.libs.finder.session").current()
t.ok("the parked level is marked", session.stack[1].stale == true)
H.press("<C-o>")
H.settle(500)
t.ok("and loaded again when shown", session.level.stale ~= true and H.title() == "Files")
H.close()

t.section("fuzzy highlights of the files do not leak into the grep")
H.open("files", { cwd = dir })
H.settle(500)
H.type("lua")
local list_buf = H.panes().list.buf
t.ok("files rows are highlighted", next(require("beast.libs.finder.match_hl").list_ranges(list_buf)) ~= nil)
H.press("<C-g>")
H.settle(300)
t.eq("placeholder row has no highlight", next(require("beast.libs.finder.match_hl").list_ranges(list_buf)), nil)
H.type("hello", 600)
t.eq("grep rows have no leftover highlight", next(require("beast.libs.finder.match_hl").list_ranges(list_buf)), nil)
H.close()

t.section("refusals")
local toasts = {}
_G.Toast = function(msg)
	toasts[#toasts + 1] = msg
end
H.open("files", { cwd = dir })
H.settle(500)
H.type("zzzznomatch")
H.press("<C-g>")
t.eq("nothing matched: toast, no new level", { toasts[#toasts], H.title() }, { "Nothing to open from here", "Files" })
H.close()

H.list_source("zz_chain_none", { "x" })
H.open("zz_chain_none")
H.press("<C-g>")
t.eq("no edge from this source: toast", toasts[#toasts], "Nothing to open from here")
H.press("<BS>")
t.eq("<BS> on the first level does nothing special", H.title(), "Zz chain none")
H.close()

vim.fn.delete(dir, "rf")
t.done()
