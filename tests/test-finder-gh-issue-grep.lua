-- =========================================================================
-- Test: issues -> grep in their title and description
-- (docs/dev-specs/finder-continuous.md, Phase 6)
--
-- Run as: nvim --clean --headless -l tests/test-finder-gh-issue-grep.lua
-- =========================================================================
local H = dofile("tests/helpers/finder.lua")
H.boot()
local gh = dofile("tests/helpers/gh.lua")
local t = H.runner()

local function issue(number, title, body)
	local raw = gh.pr(number, title)
	raw.pull_request = nil
	raw.html_url = "https://github.com/o/n/issues/" .. number
	raw.body = body
	return raw
end

gh.install()
gh.script["gh api -X GET search/issues"] = gh.ok(vim.json.encode({
	total_count = 3,
	items = {
		issue(1, "Crash on startup", "It does crash\nwhen the Config is empty"),
		issue(2, "Slow list", "Nothing to see"),
		issue(3, "Config docs", "see the config page"),
	},
}))

local opened = {}
local orig_open = vim.ui.open
---@diagnostic disable-next-line: duplicate-set-field
vim.ui.open = function(url)
	opened[#opened + 1] = url
	return {}, nil
end

H.open("gh_issue")
H.settle(400)
t.ok("issues listed", H.has_row("Crash on startup"), vim.inspect(H.rows()))
t.ok("hint offers the grep", H.hint():find("<C-g> grep 3 issues", 1, true) ~= nil, H.hint())
local searches = gh.count("gh api -X GET search/issues")

H.press("<C-g>")
H.settle(300)
t.eq("title", H.title(), "3 Issues › Live Grep")
t.ok("placeholder", H.has_row("type to search the text of the 3 issues"), vim.inspect(H.rows()))
t.ok("hint goes back", H.hint():find("<BS> back to Issues", 1, true) ~= nil, H.hint())

H.type("crash", 400)
local rows = H.rows()
t.ok(
	"issue header with number and title",
	rows[1] ~= nil and rows[1]:find("#1", 1, true) ~= nil and rows[1]:find("Crash on startup", 1, true) ~= nil,
	vim.inspect(rows)
)
t.ok("title line and body line are matches (smart case)", H.has_row("1:1") and H.has_row("2:") and H.has_row("It does crash"), vim.inspect(rows))
t.ok("an issue without the text is absent", not H.has_row("Slow list"), vim.inspect(rows))

H.type("Config", 400)
rows = H.rows()
t.ok("a capital makes it case-sensitive", H.has_row("when the Config is empty") and not H.has_row("see the config page"), vim.inspect(rows))
t.ok("each issue has its own header", H.has_row("#1") and H.has_row("#3") and not H.has_row("#2"), vim.inspect(rows))

H.type("config", 400)
t.ok("lower case matches both", H.has_row("when the Config is empty") and H.has_row("Config docs"), vim.inspect(H.rows()))

H.press("<CR>")
H.settle(300)
t.eq("Enter opens the issue in the browser", opened[1], "https://github.com/o/n/issues/1")
t.eq("Enter closes the picker", H.window_count(), 0)

H.open("gh_issue")
H.settle(400)
H.press("<C-g>")
H.settle(300)
H.type("")
H.press("<BS>")
H.settle(300)
t.ok("back to the issue list", H.has_row("Slow list"), vim.inspect(H.rows()))
t.eq("no search repeated on the way back", gh.count("gh api -X GET search/issues"), searches + 1)
H.close()

vim.ui.open = orig_open
gh.restore()
t.done()
