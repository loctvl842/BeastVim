local F = require("test.libs.finder.helpers.finder")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Configuring the chains: switch edges off, change their keys, change the back keys.

t.describe("finder chain config", function()
	local dir

	t.before_each(function()
		F.setup()
		dir = F.tmpdir({ ["a.lua"] = "hello", ["b.lua"] = "hello" })
		n.exec_lua(function()
			_G.chain = require("beast.libs.finder.chain")
			---Apply a chains configuration the way `finder.setup` does; returns the error message, if any.
			_G.setup = function(chains)
				local ok, err = pcall(require("beast.libs.finder").setup, { chains = chains })
				return not ok and tostring(err) or nil
			end
			_G.mapped = function(lhs)
				return vim.fn.maparg(lhs, "i", false, true).callback ~= nil
			end
		end)
	end)

	t.after_each(function()
		F.close()
		F.rmdir(dir)
	end)

	---Apply a chains configuration; returns the error message or nil.
	---@param chains table
	---@return string?
	local function setup(chains)
		return n.exec_lua(function(c)
			return _G.setup(c)
		end, chains)
	end

	---Is `lhs` mapped (insert mode) in the focused pane?
	---@param lhs string
	---@return boolean
	local function mapped(lhs)
		return n.exec_lua(function(l)
			return _G.mapped(l)
		end, lhs)
	end

	---Open `files` in the temp dir and type "lua".
	local function open_files()
		F.open("files", { cwd = dir })
		F.type("lua")
	end

	t.describe("defaults", function()
		t.it("are valid", function()
			t.eq(nil, setup({}))
		end)

		t.it("switch every built-in edge on", function()
			setup({})
			local ids = n.exec_lua(function()
				local ids = vim.tbl_map(function(edge)
					return edge.id
				end, _G.chain.enabled())
				table.sort(ids)
				return ids
			end)
			local expected = {
				"buffers|live_grep",
				"files|live_grep",
				"gh_commit_files|live_grep",
				"gh_commits|gh_commit_files",
				"gh_commits|live_grep",
				"gh_issue|gh_issue_grep",
				"git_branch_files|live_grep",
				"git_branches|git_branch_files",
				"git_branches|git_commits",
				"git_commit_files|live_grep",
				"git_commits|git_commit_files",
				"gh_pr|gh_commits",
				"gh_pr|gh_pr_files",
				"gh_pr_files|live_grep",
				"gl_issue|gh_issue_grep",
				"gl_mr|gh_commits",
				"gl_mr|gh_pr_files",
				"help_tags|live_grep",
			}
			table.sort(expected)
			t.eq(expected, ids)
		end)

		t.it("use <C-g> but the commits of a pull or merge request or a branch (<C-t>) and the grep of a commit (<C-f>)", function()
			setup({})
			t.eq(
				true,
				n.exec_lua(function()
					return vim.iter(_G.chain.enabled()):all(function(edge)
						local commits = edge.id == "gh_pr|gh_commits" or edge.id == "gl_mr|gh_commits" or edge.id == "git_branches|git_commits"
						return edge.key == ((commits and "<C-t>") or (edge.id == "gh_commits|live_grep" and "<C-f>") or "<C-g>")
					end)
				end)
			)
		end)

		t.it("use <BS> and <C-o> as back keys", function()
			t.eq(
				{ "<BS>", "<C-o>" },
				n.exec_lua(function()
					return require("beast.libs.finder.config").chains.back
				end)
			)
		end)

		t.it("bind the default keys and show them in the hint", function()
			setup({})
			open_files()
			t.eq(true, mapped("<C-g>"))
			t.eq(true, mapped("<C-o>") and mapped("<BS>"))
			t.eq(true, F.hint():find("<C-g> grep 2 files", 1, true) ~= nil)
		end)
	end)

	t.describe("an edge switched off", function()
		t.before_each(function()
			t.eq(nil, setup({ edges = { ["files|live_grep"] = false } }))
		end)

		t.it("is not enabled but still exists for chain.edge", function()
			t.eq(
				{ 0, true },
				n.exec_lua(function()
					return { #_G.chain.from("files"), _G.chain.edge("files", "live_grep") ~= nil }
				end)
			)
		end)

		t.it("shows no hint and its key follows nothing (muted: other pickers still use it)", function()
			open_files()
			t.eq("", F.hint())
			F.press("<C-g>")
			t.eq("Files", F.title())
		end)

		t.it("does not affect other edges", function()
			t.eq(
				true,
				n.exec_lua(function()
					return #_G.chain.from("buffers") == 1
				end)
			)
		end)
	end)

	t.describe("a key changed", function()
		t.before_each(function()
			t.eq(nil, setup({ edges = { ["files|live_grep"] = { key = "<M-g>" } } }))
			open_files()
		end)

		t.it("binds the new key", function()
			t.eq(true, mapped("<M-g>"))
		end)

		t.it("makes the old key follow nothing and the hint show the new one", function()
			F.press("<C-g>")
			t.eq("Files", F.title())
			t.eq(true, F.hint():find("<M-g> grep 2 files", 1, true) ~= nil)
		end)

		t.it("makes the new key follow the edge", function()
			F.press("<M-g>")
			F.settle(200)
			t.eq("2 Files › Live Grep", F.title())
		end)

		t.it("compares keys as keys, not as text", function()
			t.eq(
				true,
				n.exec_lua(function()
					return _G.chain.same_key("<c-g>", "<C-g>")
				end)
			)
		end)
	end)

	t.describe("two ways down from one list", function()
		t.it("is valid when the files-changed edge is off and commits take <C-g>", function()
			t.eq(nil, setup({ edges = { ["gh_pr|gh_pr_files"] = false, ["gh_pr|gh_commits"] = { key = "<C-g>" } } }))
		end)

		t.it("leaves one edge from the pull requests, with the new key", function()
			setup({ edges = { ["gh_pr|gh_pr_files"] = false, ["gh_pr|gh_commits"] = { key = "<C-g>" } } })
			t.eq(
				{ 1, "<C-g>" },
				n.exec_lua(function()
					local from = _G.chain.from("gh_pr")
					return { #from, from[1].key }
				end)
			)
		end)
	end)

	t.describe("back keys", function()
		t.before_each(function()
			t.eq(nil, setup({ back = { "<C-b>" } }))
			open_files()
			F.press("<C-g>")
			F.settle(200)
		end)

		t.it("shows the first back key in the hint", function()
			t.eq(true, F.hint():find("<C-b> back to Files", 1, true) ~= nil)
		end)

		t.it("no longer binds <BS> as a back key", function()
			t.eq(
				true,
				n.exec_lua(function()
					return vim.fn.maparg("<BS>", "i", false, true).callback == nil
				end)
			)
		end)

		t.it("goes back with the configured key", function()
			F.press("<C-b>")
			F.settle(200)
			t.eq("Files", F.title())
		end)
	end)

	t.describe("an invalid configuration raises", function()
		for _, case in ipairs({
			{ "an unknown edge", { edges = { ["files|buffers"] = false } }, "unknown chain 'files|buffers'" },
			{ "an edge that is neither a table nor false", { edges = { ["files|live_grep"] = true } }, "must be false or" },
			{ "a key that is not a string", { edges = { ["files|live_grep"] = { key = 5 } } }, "must be false or" },
			{ "an empty key", { edges = { ["files|live_grep"] = { key = "" } } }, "must be false or" },
			{ "a key of the picker", { edges = { ["files|live_grep"] = { key = "<C-j>" } } }, "already used by the picker" },
			{ "an empty back list", { back = {} }, "at least one key" },
			{ "a back key that is not a string", { back = { 1 } }, "not a string" },
			{ "a back key of the picker", { back = { "<C-k>" } }, "already used by the picker" },
			{
				"two edges of one source sharing a key",
				{ edges = { ["gh_pr|gh_commits"] = { key = "<C-g>" } } },
				"both use '<C-g>' from 'gh_pr'",
			},
			{
				"an edge key equal to a back key",
				{ back = { "<C-b>" }, edges = { ["files|live_grep"] = { key = "<C-b>" } } },
				"also a back key",
			},
		}) do
			t.it("on " .. case[1], function()
				local err = setup(case[2])
				t.eq(true, err ~= nil and err:find(case[3], 1, true) ~= nil)
			end)
		end
	end)
end)
