-- =========================================================================
-- Test: pull requests -> files changed (the chain through the real picker, gh scripted)
-- (docs/dev-specs/finder-continuous.md, Phase 4)
--
-- Run as: nvim --clean --headless -l tests/test-finder-gh-pr-files.lua
-- =========================================================================
local H = dofile("tests/helpers/finder.lua")
H.boot()
local gh = dofile("tests/helpers/gh.lua")
local t = H.runner()

local long_title = "Refactor the finder so that every picker can lead to the next one"
gh.install()
gh.script["gh api -X GET search/issues"] = gh.ok(vim.json.encode({
	total_count = 2,
	items = { gh.pr(1, "Short title"), gh.pr(2, long_title) },
}))
local function page(n, number)
	return ("gh api -X GET repos/o/n/pulls/%d/files --hostname github.com -f per_page=100 -f page=%d"):format(number, n)
end
gh.script[page(1, 1)] = gh.ok(vim.json.encode(gh.files(3)))
local files2 = gh.files(2, "lib/mod")
files2[2].patch = nil
gh.script[page(1, 2)] = gh.ok(vim.json.encode(files2))

local toasts = {}
_G.Toast = function(msg)
	toasts[#toasts + 1] = msg
end

H.open("gh_pr")
H.settle(400)
t.ok("the pull requests are listed", H.has_row("Short title"), vim.inspect(H.rows()))
t.ok("hint names the first pull request", H.hint():find("<C-g> files changed in #1", 1, true) ~= nil, H.hint())
local searches = gh.count("gh api -X GET search/issues")

H.press("<C-g>")
H.settle(400)
t.eq("title of the first pull request", H.title(), "PR Short title › Files Changed (3)")
t.eq("only paths are listed", { H.has_row("f1.lua"), H.has_row("f3.lua") }, { true, true })
t.eq("count shows the number of files", H.count(), "3")
t.ok("hint offers the grep and the way back", H.hint():find("<BS> back to Pull Requests", 1, true) ~= nil, H.hint())
local preview = H.panes().preview
local text = table.concat(vim.api.nvim_buf_get_lines(preview.buf, 0, -1, false), "\n")
t.ok("preview shows the diff of the first file", text:find("new 1", 1, true) ~= nil and text:find("+new 1", 1, true) == nil, text)
t.eq("the code has no filetype of its own", vim.bo[preview.buf].filetype, "")
local plines = vim.api.nvim_buf_get_lines(preview.buf, 0, -1, false)
t.eq(
	"header, hunk band, removed, added",
	{ plines[1]:match("^modified%s+%+1 %-1"), plines[2], plines[3], plines[4] },
	{ "modified  +1 -1", "▸ @@ -1 +1 @@", "old 1", "new 1" }
)
local function gutter(lnum)
	return vim.api.nvim_eval_statusline(vim.wo[preview.win].statuscolumn, { winid = preview.win, use_statuscol_lnum = lnum }).str
end
t.eq("the removed line shows its old number and a minus", gutter(3), " 1    - ")
t.eq("the added line shows its new number and a plus", gutter(4), "    1 + ")
t.eq("long lines wrap in the pane", vim.wo[preview.win].wrap, true)

H.press("<C-j>")
H.settle(300)
text = table.concat(vim.api.nvim_buf_get_lines(preview.buf, 0, -1, false), "\n")
t.ok("moving shows the next diff", text:find("new 2", 1, true) ~= nil, text)

H.type("f3")
t.eq("typing filters by path", { H.has_row("f3.lua"), H.has_row("f1.lua") }, { true, false })
t.eq("count shows matches over total", H.count(), "1/3")

H.type("")
H.press("<BS>")
H.settle(300)
t.eq("back to the pull requests", H.title():match("^Pull Requests") ~= nil, true)
t.eq("the pull request preview has no diff gutter", { vim.wo[preview.win].statuscolumn, vim.wo[preview.win].signcolumn }, { "", "auto" })
t.eq("no new search was made", gh.count("gh api -X GET search/issues"), searches)
t.ok("the list is still there", H.has_row("Short title"), vim.inspect(H.rows()))

H.press("<C-j>")
H.settle(300)
H.press("<C-g>")
H.settle(400)
t.eq("a long title is trimmed with ...", H.title(), "PR Refactor the finder so that every pic... › Files Changed (2)")
H.press("<C-j>")
H.settle(300)
local lines = vim.api.nvim_buf_get_lines(H.panes().preview.buf, 0, -1, false)
t.ok("a file with no patch says so", vim.tbl_contains(lines, "(diff too large or binary)"), vim.inspect(lines))

-- Enter shows the diff of the file in a scratch buffer
H.press("<CR>")
H.settle(300)
local buf = vim.api.nvim_get_current_buf()
t.eq("Enter closes the picker", H.window_count(), 0)
t.eq("diff buffer is a diff", vim.bo[buf].filetype, "diff")
t.eq("diff buffer is read-only", vim.bo[buf].modifiable, false)
t.ok(
	"diff buffer is named after the pull request file",
	vim.api.nvim_buf_get_name(buf):find("o/n#2: lib/mod2.lua", 1, true) ~= nil,
	vim.api.nvim_buf_get_name(buf)
)

-- Errors
gh.script[page(1, 1)] = gh.fail("gh: Not Found (HTTP 404)")
H.open("gh_pr")
H.settle(400)
H.press("<C-g>")
H.settle(400)
t.ok("an error is a message row", H.has_row("GitHub could not list the files"), vim.inspect(H.rows()))
H.press("<C-g>")
t.eq("no chain from a message row", toasts[#toasts], "Nothing to open from here")
H.close()

gh.restore()
t.done()
