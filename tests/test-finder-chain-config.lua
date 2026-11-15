-- =========================================================================
-- Test: configuring the chains (switch edges off, change their keys, change the back keys)
-- (docs/dev-specs/finder-pr-commits.md, Phase 1)
--
-- Run as: nvim --clean --headless -l tests/test-finder-chain-config.lua
-- =========================================================================
local H = dofile("tests/helpers/finder.lua")
H.boot()
local t = H.runner()
local chain = require("beast.libs.finder.chain")
local config = require("beast.libs.finder.config")

local toasts = {}
_G.Toast = function(msg)
	toasts[#toasts + 1] = msg
end

local dir = vim.fn.resolve(vim.fn.tempname())
vim.fn.mkdir(dir, "p")
vim.fn.writefile({ "hello" }, dir .. "/a.lua")
vim.fn.writefile({ "hello" }, dir .. "/b.lua")
vim.cmd("cd " .. vim.fn.fnameescape(dir))

--- Apply a chains configuration the way `finder.setup` does; returns the error message, if any.
local function setup(chains)
	local ok, err = pcall(H.finder().setup, { chains = chains })
	return not ok and tostring(err) or nil
end

local function mapped(lhs)
	local map = vim.fn.maparg(lhs, "i", false, true)
	return map.callback ~= nil
end

t.section("defaults")
t.eq("defaults are valid", setup({}), nil)
local ids = vim.tbl_map(function(edge)
	return edge.id
end, chain.enabled())
local expected = {
	"buffers|live_grep",
	"files|live_grep",
	"gh_issue|gh_issue_grep",
	"gh_pr|gh_pr_files",
	"gh_pr_files|live_grep",
	"help_tags|live_grep",
}
table.sort(ids)
table.sort(expected)
t.eq("every built-in edge is on", ids, expected)
t.ok(
	"all use <C-g>",
	vim.iter(chain.enabled()):all(function(edge)
		return edge.key == "<C-g>"
	end)
)
t.eq("back keys", config.chains.back, { "<BS>", "<C-o>" })
H.open("files", { cwd = dir })
H.type("lua")
t.ok("the default key is bound", mapped("<C-g>"))
t.ok("the default back keys are bound", mapped("<C-o>") and mapped("<BS>"))
t.ok("the hint shows the default key", H.hint():find("<C-g> grep 2 files", 1, true) ~= nil, H.hint())
H.close()

t.section("an edge switched off")
t.eq("valid", setup({ edges = { ["files|live_grep"] = false } }), nil)
t.eq("the edge is not enabled", #chain.from("files"), 0)
t.ok("but still exists for chain.edge", chain.edge("files", "live_grep") ~= nil)
H.open("files", { cwd = dir })
H.type("lua")
t.eq("no hint", H.hint(), "")
t.ok("the key is not even bound", not mapped("<C-g>"))
H.close()
t.ok("other edges are not affected", #chain.from("buffers") == 1)

t.section("a key changed")
t.eq("valid", setup({ edges = { ["files|live_grep"] = { key = "<M-g>" } } }), nil)
H.open("files", { cwd = dir })
H.type("lua")
t.ok("the new key is bound, the old one is not", mapped("<M-g>") and not mapped("<C-g>"))
t.ok("hint shows the new key", H.hint():find("<M-g> grep 2 files", 1, true) ~= nil, H.hint())
H.press("<M-g>")
H.settle(200)
t.eq("the new key follows the edge", H.title(), "2 Files › Live Grep")
H.close()
t.ok("keys are compared as keys, not as text", chain.same_key("<c-g>", "<C-g>"))

t.section("back keys")
t.eq("valid", setup({ back = { "<C-b>" } }), nil)
H.open("files", { cwd = dir })
H.type("lua")
H.press("<C-g>")
H.settle(200)
t.ok("hint shows the first back key", H.hint():find("<C-b> back to Files", 1, true) ~= nil, H.hint())
t.ok("<BS> is no longer a back key", vim.fn.maparg("<BS>", "i", false, true).callback == nil)
H.press("<C-b>")
H.settle(200)
t.eq("the configured key goes back", H.title(), "Files")
H.close()

t.section("invalid configuration raises")
local function raises(name, chains, needle)
	local err = setup(chains)
	t.ok(name, err ~= nil and err:find(needle, 1, true) ~= nil, tostring(err))
end
raises("unknown edge", { edges = { ["files|buffers"] = false } }, "unknown chain 'files|buffers'")
raises("not a table or false", { edges = { ["files|live_grep"] = true } }, "must be false or")
raises("key not a string", { edges = { ["files|live_grep"] = { key = 5 } } }, "must be false or")
raises("empty key", { edges = { ["files|live_grep"] = { key = "" } } }, "must be false or")
raises("key of the picker", { edges = { ["files|live_grep"] = { key = "<C-j>" } } }, "already used by the picker")
raises("back list empty", { back = {} }, "at least one key")
raises("back key not a string", { back = { 1 } }, "not a string")
raises("back key of the picker", { back = { "<C-k>" } }, "already used by the picker")
raises("edge key equals a back key", { back = { "<C-b>" }, edges = { ["files|live_grep"] = { key = "<C-b>" } } }, "also a back key")

setup({})
vim.fn.delete(dir, "rf")
t.done()
