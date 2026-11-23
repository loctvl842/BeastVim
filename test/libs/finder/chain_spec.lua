local F = require("test.libs.finder.helpers.finder")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Chains: the closed edge map, the keys, the hint line and scoped grep.
-- Needs fd or rg, and rg, on PATH.

t.describe("finder chain", function()
	t.before_each(F.setup)

	t.after_each(F.close)

	t.describe("closed edge map", function()
		t.it("has files -> live_grep", function()
			t.eq(
				"live_grep",
				n.exec_lua(function()
					return require("beast.libs.finder.chain").edge("files", "live_grep").to
				end)
			)
		end)

		for _, pair in ipairs({
			{ "live_grep", "files" },
			{ "live_grep", "gh_pr" },
			{ "colorschemes", "files" },
			{ "files", "buffers" },
		}) do
			t.it(("raises for %s -> %s"):format(pair[1], pair[2]), function()
				local ok, err = unpack(n.exec_lua(function(from, to)
					local ok, err = pcall(require("beast.libs.finder.chain").edge, from, to)
					return { ok, tostring(err) }
				end, pair[1], pair[2]))
				t.eq(false, ok)
				t.eq(true, err:find(pair[1] .. " -> " .. pair[2], 1, true) ~= nil)
			end)
		end

		t.it("has exactly the built-in edges, every other pair raises", function()
			local r = n.exec_lua(function()
				local chain = require("beast.libs.finder.chain")
				local sources = {}
				for _, path in ipairs(vim.fn.globpath("lua/beast/libs/finder/source", "*.lua", false, true)) do
					local name = vim.fn.fnamemodify(path, ":t:r")
					if name ~= "init" then
						sources[#sources + 1] = name
					end
				end
				sources[#sources + 1] = "live_grep"
				local valid = {
					["files>live_grep"] = true,
					["buffers>live_grep"] = true,
					["help_tags>live_grep"] = true,
					["gh_pr>gh_pr_files"] = true,
					["gh_pr>gh_commits"] = true,
					["gh_commits>live_grep"] = true,
					["gh_commits>gh_commit_files"] = true,
					["gh_commit_files>live_grep"] = true,
					["git_commits>git_commit_files"] = true,
					["git_commit_files>live_grep"] = true,
					["git_branches>git_branch_files"] = true,
					["git_branches>git_commits"] = true,
					["git_branch_files>live_grep"] = true,
					["gh_pr_files>live_grep"] = true,
					["gh_issue>gh_issue_grep"] = true,
					["gl_mr>gh_pr_files"] = true,
					["gl_mr>gh_commits"] = true,
					["gl_issue>gh_issue_grep"] = true,
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
				return { wrong = wrong, many_sources = #sources >= 12 }
			end)
			t.eq(true, r.many_sources)
			t.eq({}, r.wrong)
		end)

		t.it("lists the enabled edges through finder.chains()", function()
			t.eq(
				true,
				n.exec_lua(function()
					return #require("beast.libs.finder").chains() == #require("beast.libs.finder.chains")
				end)
			)
		end)
	end)

	t.describe("files -> grep", function()
		local dir

		t.before_each(function()
			dir = F.tmpdir({
				["a.lua"] = "hello alpha",
				["b.lua"] = "hello beta",
				["nested/d.lua"] = "hello delta",
				["c.txt"] = "hello text",
			})
			F.open("files", { cwd = dir })
			F.settle(500)
			F.type("lua")
		end)

		t.after_each(function()
			F.rmdir(dir)
		end)

		---Press <C-g> to drill into the grep.
		local function drill()
			F.press("<C-g>")
			F.settle(200)
		end

		t.it("shows the matches over the total in the count", function()
			t.eq("3/4", F.count())
		end)

		t.it("offers the grep in the hint, with no way back at the first level", function()
			local hint = F.hint()
			t.eq(true, hint:find("<C-g> grep 3 files", 1, true) ~= nil)
			t.eq(true, hint:find("<BS>", 1, true) == nil)
		end)

		t.it("titles the scoped grep and starts with an empty prompt", function()
			drill()
			t.eq("3 Files › Live Grep", F.title())
			t.eq("", F.prompt())
		end)

		t.it("has an empty preview with no stale title for the placeholder", function()
			drill()
			t.eq(
				{ "", 1 },
				n.exec_lua(function()
					local preview = FH.panes().preview
					local cfg = vim.api.nvim_win_get_config(preview.win)
					local title = type(cfg.title) == "table" and cfg.title[1] and cfg.title[1][1] or cfg.title or ""
					return { vim.trim(title), #vim.api.nvim_buf_get_lines(preview.buf, 0, -1, false) }
				end)
			)
		end)

		t.it("says what to type and offers the way back", function()
			drill()
			t.eq(true, F.has_row("type to search inside the 3 files"))
			t.eq(true, F.hint():find("<BS> back to Files", 1, true) ~= nil)
		end)

		t.it("searches only the scoped files", function()
			drill()
			F.type("hello", 600)
			t.eq(true, F.has_row("a.lua"))
			t.eq(true, F.has_row("d.lua"))
			t.eq(false, F.has_row("c.txt"))
		end)

		t.it("returns to the files on an empty <BS>, prompt as left", function()
			drill()
			F.type("")
			F.press("<BS>")
			F.settle(200)
			t.eq("lua", F.prompt())
			t.eq("3/4", F.count())
			t.eq("Files", F.title())
		end)

		t.it("returns on <C-o> too", function()
			drill()
			F.press("<C-o>")
			F.settle(200)
			t.eq("Files", F.title())
		end)

		t.it("treats <BS> with text as a normal backspace (stays in grep)", function()
			drill()
			F.type("h", 300)
			F.press("<BS>")
			t.eq("3 Files › Live Grep", F.title())
		end)

		t.it("leaves no hint line behind when closed", function()
			drill()
			F.close()
			t.eq("", F.hint())
		end)
	end)

	t.describe("buffers -> grep", function()
		local dir

		t.before_each(function()
			dir = F.tmpdir({
				["a.lua"] = "hello alpha",
				["b.lua"] = "hello beta",
				["c.txt"] = "hello text",
			})
			n.exec_lua(function(d)
				for _, name in ipairs({ "a.lua", "c.txt" }) do
					vim.cmd("edit " .. vim.fn.fnameescape(d .. "/" .. name))
				end
				vim.cmd("enew") -- a nameless buffer
			end, dir)
			F.open("buffers", { cwd = dir })
			F.settle(300)
			F.type("lua")
			F.press("<C-g>")
			F.settle(200)
		end)

		t.after_each(function()
			F.rmdir(dir)
		end)

		t.it("names the scoped buffers in the title and the way back in the hint", function()
			t.eq("1 Buffers › Live Grep", F.title())
			t.eq(true, F.hint():find("<BS> back to Buffers", 1, true) ~= nil)
		end)

		t.it("searches only the open scoped buffers", function()
			F.type("hello", 600)
			t.eq(true, F.has_row("a.lua"))
			t.eq(false, F.has_row("b.lua"))
		end)
	end)

	t.describe("help -> grep", function()
		t.before_each(function()
			F.open("help_tags")
			F.settle(500)
			F.type("nvim_buf_set_lines")
			F.press("<C-g>")
			F.settle(300)
		end)

		t.it("counts help files in the title", function()
			t.matches("^%d+ Help Files › Live Grep$", F.title())
		end)

		t.it("finds a hit inside a help page", function()
			F.type("nvim_buf_set_lines", 800)
			t.eq(true, F.has_row("api.txt"))
		end)

		t.it("goes back to the tags", function()
			F.type("nvim_buf_set_lines", 800)
			F.press("<BS>")
			F.type("")
			F.press("<BS>")
			F.settle(200)
			t.eq("Help tags", F.title())
		end)
	end)

	t.describe("with the files list open", function()
		local dir

		t.before_each(function()
			dir = F.tmpdir({
				["a.lua"] = "hello alpha",
				["b.lua"] = "hello beta",
				["nested/d.lua"] = "hello delta",
				["c.txt"] = "hello text",
			})
			F.open("files", { cwd = dir })
			F.settle(500)
		end)

		t.after_each(function()
			F.rmdir(dir)
		end)

		t.it("brings the hint back after it was hidden", function()
			F.type("lua")
			t.eq(true, F.hint() ~= "")
			F.type("zzzzqq")
			t.eq("", F.hint())
			F.type("lua")
			t.eq(true, F.hint():find("<C-g> grep", 1, true) ~= nil)
		end)

		t.it("refuses a drill before the typed text was searched", function()
			n.exec_lua(function()
				local input = FH.panes().input
				local prefix = require("beast.libs.finder.config").prompt_prefix
				vim.api.nvim_buf_set_lines(input.buf, 0, 1, false, { prefix .. "b" }) -- typed, debounce not fired
			end)
			F.press("<C-g>")
			t.eq("Still searching - try again in a moment", F.last_toast())
			t.eq("Files", F.title())
		end)

		t.it("reloads a parked level when hidden files are toggled", function()
			F.press("<C-g>")
			F.settle(200)
			n.exec_lua(function()
				vim.api.nvim_exec_autocmds("User", { pattern = "BeastVisibilityChanged" })
			end)
			F.settle(300)
			t.eq(
				true,
				n.exec_lua(function()
					return require("beast.libs.finder.session").current().stack[1].stale == true
				end)
			)
			F.press("<C-o>")
			F.settle(500)
			t.eq(
				true,
				n.exec_lua(function()
					return require("beast.libs.finder.session").current().level.stale ~= true
				end)
			)
			t.eq("Files", F.title())
		end)

		t.describe("fuzzy highlights of the files", function()
			---Does the list buffer carry any fuzzy highlight range?
			local function highlighted()
				return n.exec_lua(function()
					return next(require("beast.libs.finder.match_hl").list_ranges(FH.panes().list.buf)) ~= nil
				end)
			end

			t.it("exist on the files rows", function()
				F.type("lua")
				t.eq(true, highlighted())
			end)

			t.it("do not leak into the placeholder row of the grep", function()
				F.type("lua")
				F.press("<C-g>")
				F.settle(300)
				t.eq(false, highlighted())
			end)

			t.it("do not leak into the grep rows", function()
				F.type("lua")
				F.press("<C-g>")
				F.settle(300)
				F.type("hello", 600)
				t.eq(false, highlighted())
			end)
		end)

		t.it("refuses when nothing matched: toast, no new level", function()
			F.type("zzzznomatch")
			F.press("<C-g>")
			t.eq("Nothing to open from here", F.last_toast())
			t.eq("Files", F.title())
		end)
	end)

	t.describe("a source without edges", function()
		t.before_each(function()
			n.exec_lua(function()
				FH.list_source("zz_chain_none", { "x" })
			end)
			F.open("zz_chain_none")
		end)

		-- The old test asserted a toast here, but it only saw the one left by an earlier refusal:
		-- the key is muted for a source without edges, so nothing happens at all.
		t.it("does nothing on <C-g>", function()
			F.press("<C-g>")
			t.eq({}, F.toasts())
			t.eq("Zz chain none", F.title())
		end)

		t.it("does nothing special on <BS> at the first level", function()
			F.press("<BS>")
			t.eq("Zz chain none", F.title())
		end)
	end)
end)
