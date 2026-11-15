-- =========================================================================
-- Test: a scope bigger than the 1000 rows a list keeps is still searched in full
-- (docs/dev-specs/finder-continuous.md, success criteria)
--
-- Run as: nvim --clean --headless -l tests/test-finder-chain-large.lua
-- =========================================================================
local H = dofile("tests/helpers/finder.lua")
H.boot()
local t = H.runner()

local dir = vim.fn.resolve(vim.fn.tempname())
vim.fn.mkdir(dir, "p")
local total = 1300
for i = 1, total do
	vim.fn.writefile({ "needle " .. i }, ("%s/f%04d.lua"):format(dir, i))
end
-- The last file (worst fuzzy rank for "f") must be reachable by the grep.
vim.cmd("cd " .. vim.fn.fnameescape(dir))

H.open("files", { cwd = dir })
H.settle(1500)
H.type("f")
t.eq("count has all the matches, not the 1000 shown", H.count(), tostring(total))
H.press("<C-g>")
H.settle(300)
t.eq("title counts every file", H.title(), total .. " Files › Live Grep")
H.type("needle " .. total, 1500)
t.ok("a file beyond the first 1000 is found", H.has_row("f" .. total .. ".lua") or H.has_row("f1300.lua"), vim.inspect(H.rows()))
H.close()

vim.fn.delete(dir, "rf")
t.done()
