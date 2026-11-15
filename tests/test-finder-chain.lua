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
t.eq("finder.chains() is the same table", require("beast.libs.finder").chains(), require("beast.libs.finder.chains"))

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
