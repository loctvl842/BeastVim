local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

---Child-side setup shared by the explorer specs: globals the real config publishes beyond `h.clear()`.
local function publish_extra_globals()
	n.exec_lua(function()
		_G.Icon = require("beast.icon")
		_G.Toast = function() end
	end)
end

---Create a root with a few files and open a real explorer on it; `_G.ex` holds handles and helpers.
local function open_explorer()
	n.exec_lua(function()
		local function write(path)
			vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
			vim.fn.writefile({ "x" }, path)
		end
		local root = vim.fn.resolve(vim.fn.tempname())
		write(root .. "/lua/beast/init.lua")
		write(root .. "/lua/beast/libs/explorer/init.lua")
		write(root .. "/lua/beast/libs/finder/init.lua")
		write(root .. "/README.md")
		local explorer = require("beast.libs.explorer")
		explorer.setup({})
		explorer.open(root)
		local state = require("beast.libs.explorer.state")
		local ex = {
			root = root,
			write = write,
			explorer = explorer,
			search = require("beast.libs.explorer.search"),
			state = state,
			ui = require("beast.libs.explorer.ui"),
			view_buf = state.view.buf,
			view_win = state.view.win,
			real_tree = state.tree,
		}
		function ex.buf_lines()
			return vim.api.nvim_buf_get_lines(ex.view_buf, 0, -1, false)
		end
		function ex.wait_count(count)
			vim.wait(3000, function()
				return state.mode == "search" and state
					.tree--[[@as Beast.Explorer.SearchTree]]
					.count == count and not state.mode_state.loading
			end, 10)
		end
		function ex.row_of(name)
			for i, l in ipairs(ex.buf_lines()) do
				if l:find(name, 1, true) then
					return i
				end
			end
		end
		function ex.title()
			return vim.fn.fnamemodify(root, ":t"):upper()
		end
		---True when `buf` has a buffer-local normal-mode mapping for `lhs`.
		function ex.has_map(buf, lhs)
			local raw = vim.api.nvim_replace_termcodes(lhs, true, true, true)
			for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
				if m.lhsraw == raw then
					return true
				end
			end
			return false
		end
		_G.ex = ex
	end)
end

t.describe("explorer search", function()
	t.before_each(function()
		h.clear()
		publish_extra_globals()
	end)

	t.after_each(function()
		n.exec_lua(function()
			if _G.ex then
				vim.fn.delete(_G.ex.root, "rf")
			end
		end)
	end)

	t.describe("without the finder", function()
		-- / and ? keep their Neovim meaning
		t.before_each(function()
			n.exec_lua(function()
				package.loaded["beast.libs.finder.search"] = {
					available = function()
						return false
					end,
				}
			end)
			open_explorer()
		end)

		local function mapped(lhs)
			return n.exec_lua(function(l)
				return _G.ex.has_map(_G.ex.state.view.buf, l)
			end, lhs)
		end

		t.it("does not map /", function()
			t.eq(false, mapped("/"))
		end)
		t.it("does not map ?", function()
			t.eq(false, mapped("?"))
		end)
		t.it("does not map <Esc><Esc>", function()
			t.eq(false, mapped("<Esc><Esc>"))
		end)
		t.it("still maps other keys", function()
			t.eq(true, mapped("<CR>"))
		end)
	end)

	t.describe("SearchTree.from_matches", function()
		---@return { names: string[], is_subclass: boolean, count: integer, capped: boolean, positions: boolean }
		local function build()
			return n.exec_lua(function()
				local SearchTree = require("beast.libs.explorer.search.tree")
				local Tree = require("beast.libs.explorer.tree")
				local st = SearchTree.from_matches("/r", {
					{ text = "lua/beast/libs/explorer/init.lua", positions = { 25, 26, 27, 28, 29, 30, 31, 32 } },
					{ text = "lua/beast/init.lua", positions = { 11, 12, 13, 14, 15, 16, 17, 18 } },
					{ text = "README.md" },
				}, true)
				local names = {}
				for _, node in ipairs(st:flat({ show_hidden = true })) do
					names[#names + 1] = string.rep(" ", node.depth) .. node.name .. (node.last and "$" or "")
				end
				local pos = st.positions["/r/lua/beast/init.lua"]
				return {
					names = names,
					is_subclass = getmetatable(st) == SearchTree and SearchTree.flat == Tree.flat,
					count = st.count,
					capped = st.capped,
					positions = pos ~= nil and pos[0] ~= nil and pos[7] ~= nil,
				}
			end)
		end

		t.it("orders dirs first, then files, depth-indented", function()
			local names = build().names
			local a = { "lua", " beast", "  libs", "   explorer$", "    init.lua$", "  init.lua$", "README.md$" }
			local b = { "lua", " beast$", "  libs", "   explorer$", "    init.lua$", "  init.lua$", "README.md$" }
			t.eq(true, vim.deep_equal(names, a) or vim.deep_equal(names, b), vim.inspect(names))
		end)
		t.it("is a Tree subclass", function()
			t.eq(true, build().is_subclass)
		end)
		t.it("keeps count and capped", function()
			local r = build()
			t.eq({ 3, true }, { r.count, r.capped })
		end)
		t.it("maps matched letters to the name (0-based)", function()
			t.eq(true, build().positions)
		end)
	end)

	t.describe("search.prompt.ask", function()
		-- Typed keys are queued, then read by getcharstr.
		---@param keys string
		---@param default? string
		---@return { text: string?, changes: string[], cancelled: boolean }
		local function typed(keys, default)
			return n.exec_lua(function(k, d)
				local prompt = require("beast.libs.explorer.search.prompt")
				local changes = {}
				vim.api.nvim_feedkeys(vim.keycode(k), "t", false)
				local text = prompt.ask(d, function(s)
					changes[#changes + 1] = s
				end)
				return { text = text, changes = changes, cancelled = text == nil }
			end, keys, default or "")
		end

		t.it("characters and <BS> edit the text", function()
			t.eq("abd", typed("abc<BS>d<CR>").text)
		end)
		t.it("on_change fires per edit", function()
			local r = typed("abc<BS>d<CR>")
			t.eq(5, #r.changes)
			t.eq("abd", r.changes[5])
		end)
		t.it("<C-w> deletes a word", function()
			t.eq("foo", typed("foo bar<C-w><CR>").text)
		end)
		t.it("<C-u> clears", function()
			t.eq("x", typed("foo<C-u>x<CR>").text)
		end)
		t.it("default text is kept and editable", function()
			t.eq("abc", typed("c<CR>", "ab").text)
		end)
		t.it("<Esc> cancels", function()
			t.eq(true, typed("abc<Esc>").cancelled)
		end)
	end)

	t.describe("lifecycle against a real explorer window", function()
		t.before_each(open_explorer)

		t.describe("start()", function()
			t.it("normal title has no mode label and mode is normal by default", function()
				t.eq(
					{ true, "normal", true },
					n.exec_lua(function()
						local ex = _G.ex
						return {
							vim.trim(ex.buf_lines()[1]) == ex.title(),
							ex.state.mode,
							ex.state.mode_state == nil,
						}
					end)
				)
			end)

			t.it("switches to search mode with a SearchTree", function()
				t.eq(
					{ "search", true, true },
					n.exec_lua(function()
						local ex = _G.ex
						ex.search.start()
						local SearchTree = require("beast.libs.explorer.search.tree")
						return {
							ex.state.mode,
							ex.search.is_active(),
							getmetatable(ex.state.tree) == SearchTree and ex.state.tree ~= ex.real_tree,
						}
					end)
				)
			end)

			t.it("keeps the explorer's own buffer and window", function()
				t.eq(
					true,
					n.exec_lua(function()
						local ex = _G.ex
						ex.search.start()
						return ex.state.view.buf == ex.view_buf and vim.api.nvim_win_get_buf(ex.view_win) == ex.view_buf
					end)
				)
			end)

			t.it("starts empty: only the root title", function()
				t.eq(
					{ 1, true },
					n.exec_lua(function()
						local ex = _G.ex
						ex.search.start()
						local lines = ex.buf_lines()
						return { #lines, vim.trim(lines[1]) == ex.title() .. " (Search)" }
					end)
				)
			end)
		end)

		t.describe("set_query()", function()
			t.before_each(function()
				n.exec_lua(function()
					_G.ex.search.start()
					_G.ex.search.set_query("in.lua")
					_G.ex.wait_count(3)
				end)
			end)

			t.it("shows the title once typing ended", function()
				t.eq(
					true,
					n.exec_lua(function()
						local ex = _G.ex
						return vim.trim(ex.buf_lines()[1]) == ex.title() .. " (Search)"
					end)
				)
			end)

			t.it("shows three files plus their folders", function()
				t.eq(
					9,
					n.exec_lua(function()
						return #_G.ex.buf_lines()
					end)
				)
			end)

			t.it("puts the cursor on the first file row", function()
				t.eq(
					true,
					n.exec_lua(function()
						return vim.api.nvim_win_get_cursor(_G.ex.view_win)[1] > 1
					end)
				)
			end)

			t.it("leaves the real tree untouched", function()
				t.eq(
					true,
					n.exec_lua(function()
						local ex = _G.ex
						local lua = ex.real_tree.nodes[ex.root .. "/lua"]
						return not (lua and lua.open)
					end)
				)
			end)

			t.it("shows the query line while typing, without a trailing space", function()
				t.eq(
					{ "/ in.lua▏", false },
					n.exec_lua(function()
						local ex = _G.ex
						ex.state.mode_state.prompting = true
						ex.ui.flush()
						local line = ex.buf_lines()[1]
						return { vim.trim(line), line:match("%s$") ~= nil }
					end)
				)
			end)

			t.it("highlights the matched letters", function()
				t.eq(
					true,
					n.exec_lua(function()
						local ex = _G.ex
						ex.state.mode_state.prompting = false
						ex.ui.flush()
						local marks = vim.api.nvim_buf_get_extmarks(ex.view_buf, ex.state.view.ns, 0, -1, { details = true })
						local matched = 0
						for _, m in ipairs(marks) do
							if m[4].hl_group == "BeastExplorerSearchMatch" then
								matched = matched + 1
							end
						end
						return matched > 0
					end)
				)
			end)

			t.it("shows an empty-result message when nothing matches", function()
				t.eq(
					true,
					n.exec_lua(function()
						local ex = _G.ex
						ex.search.set_query("zzzz")
						vim.wait(3000, function()
							return ex
								.state
								.tree--[[@as Beast.Explorer.SearchTree]]
								.count == 0 and not ex.state.mode_state.loading and ex.state.mode_state.query == "zzzz"
						end, 10)
						return (ex.buf_lines()[2] or ""):find('No files match "zzzz"', 1, true) ~= nil
					end)
				)
			end)

			t.it("clears the results on an empty query", function()
				t.eq(
					1,
					n.exec_lua(function()
						_G.ex.search.set_query("")
						return #_G.ex.buf_lines()
					end)
				)
			end)
		end)

		t.describe("normal-mode features on result rows", function()
			t.before_each(function()
				n.exec_lua(function()
					local ex = _G.ex
					ex.search.start()
					ex.search.set_query("in.lua")
					ex.wait_count(3)
					vim.api.nvim_win_set_cursor(ex.view_win, { ex.row_of("lua"), 0 })
				end)
			end)

			t.it("<CR> on a folder closes it", function()
				t.eq(
					true,
					n.exec_lua(function()
						local ex = _G.ex
						local before = #ex.buf_lines()
						require("beast.libs.explorer.actions.open").run()
						return #ex.buf_lines() < before
					end)
				)
			end)

			t.it("<CR> again opens it (children collapsed, like the normal tree)", function()
				t.eq(
					true,
					n.exec_lua(function()
						local ex = _G.ex
						local before = #ex.buf_lines()
						local open = require("beast.libs.explorer.actions.open")
						open.run()
						open.run()
						return ex.row_of("beast") ~= nil and #ex.buf_lines() < before
					end)
				)
			end)

			t.it("a deleted file leaves the results and nothing else comes back", function()
				t.eq(
					{ true, true },
					n.exec_lua(function()
						local ex = _G.ex
						local open = require("beast.libs.explorer.actions.open")
						open.run()
						open.run()
						ex.state.tree:open(ex.root .. "/lua/beast/init.lua")
						ex.state.tree:open(ex.root .. "/lua/beast/libs/explorer/init.lua")
						ex.ui.render()
						local before = #ex.buf_lines()
						vim.fn.delete(ex.root .. "/lua/beast/init.lua")
						ex.state.tree:refresh(ex.root .. "/lua/beast")
						ex.ui.render()
						return {
							ex.row_of("beast/init.lua") == nil and #ex.buf_lines() == before - 1,
							ex.state.tree.nodes[ex.root .. "/lua/beast/libs"] ~= nil,
						}
					end)
				)
			end)

			t.it("a created file appears", function()
				t.eq(
					true,
					n.exec_lua(function()
						local ex = _G.ex
						local open = require("beast.libs.explorer.actions.open")
						open.run()
						open.run()
						ex.write(ex.root .. "/lua/beast/new.lua")
						ex.state.tree:refresh(ex.root .. "/lua/beast")
						ex.state.tree:open(ex.root .. "/lua/beast/new.lua")
						ex.ui.render()
						return ex.row_of("new.lua") ~= nil
					end)
				)
			end)
		end)

		t.describe("exit()", function()
			-- reveals the selected file
			---@return table
			local function exit_on_finder()
				return n.exec_lua(function()
					local ex = _G.ex
					ex.search.start()
					ex.search.set_query("finder")
					ex.wait_count(1)
					local selected = ex.state.current_node({ show_hidden = true })
					local selected_path = selected and selected.path
					ex.search.exit()
					local finder_dir = ex.state.tree.nodes[ex.root .. "/lua/beast/libs/finder"]
					local cur = ex.state.current_node({ show_hidden = true })
					return {
						selected = selected_path == ex.root .. "/lua/beast/libs/finder/init.lua",
						normal = ex.state.mode == "normal" and ex.state.mode_state == nil and not ex.search.is_active(),
						real_tree_back = ex.state.tree == ex.real_tree,
						folders_open = finder_dir ~= nil and finder_dir.open == true,
						cursor_on_file = cur ~= nil and cur.path == ex.root .. "/lua/beast/libs/finder/init.lua",
					}
				end)
			end

			t.it("starts with the cursor on finder/init.lua", function()
				t.eq(true, exit_on_finder().selected)
			end)
			t.it("returns to normal mode", function()
				t.eq(true, exit_on_finder().normal)
			end)
			t.it("brings the real tree back", function()
				t.eq(true, exit_on_finder().real_tree_back)
			end)
			t.it("opens the selected file's folders", function()
				t.eq(true, exit_on_finder().folders_open)
			end)
			t.it("puts the explorer cursor on init.lua", function()
				t.eq(true, exit_on_finder().cursor_on_file)
			end)
		end)

		t.describe("leaving the explorer window", function()
			---@return table
			local function leave()
				return n.exec_lua(function()
					local ex = _G.ex
					local other = vim.tbl_filter(function(w)
						return w ~= ex.view_win
					end, vim.api.nvim_tabpage_list_wins(0))[1]
					vim.api.nvim_win_call(other, function()
						vim.cmd("edit " .. vim.fn.fnameescape(ex.root .. "/README.md"))
					end)
					ex.search.start()
					ex.search.set_query("finder")
					ex.wait_count(1)
					vim.api.nvim_set_current_win(other)
					vim.wait(1000, function()
						return not ex.search.is_active()
					end, 10)
					local row = vim.api.nvim_win_get_cursor(ex.view_win)[1]
					local focus = vim.api.nvim_buf_get_lines(ex.view_buf, row - 1, row, false)[1]
					return {
						ended = not ex.search.is_active() and ex.state.tree == ex.real_tree,
						cursor_visible = not vim.o.guicursor:find("BeastExplorerCursor", 1, true),
						focus_stayed = vim.api.nvim_get_current_win() == other,
						on_open_file = focus:find("README.md", 1, true) ~= nil,
					}
				end)
			end

			t.it("ends search mode after focus left", function()
				t.eq(true, leave().ended)
			end)
			t.it("restores the cursor in the other window", function()
				t.eq(true, leave().cursor_visible)
			end)
			t.it("keeps focus in the other window", function()
				t.eq(true, leave().focus_stayed)
			end)
			t.it("puts the explorer cursor on the file now open", function()
				t.eq(true, leave().on_open_file)
			end)
		end)

		t.describe("root changes and stop", function()
			t.it("set_root ends search first", function()
				t.eq(
					{ "normal", true },
					n.exec_lua(function()
						local ex = _G.ex
						ex.search.start()
						ex.search.set_query("finder")
						ex.wait_count(1)
						vim.api.nvim_win_set_cursor(ex.view_win, { ex.row_of("finder"), 0 })
						require("beast.libs.explorer.actions.set_root").run()
						return { ex.state.mode, ex.state.tree.root.path == ex.root .. "/lua/beast/libs/finder" }
					end)
				)
			end)

			t.it("navigate_up goes back to the parent", function()
				t.eq(
					true,
					n.exec_lua(function()
						local ex = _G.ex
						ex.search.start()
						ex.search.set_query("finder")
						ex.wait_count(1)
						vim.api.nvim_win_set_cursor(ex.view_win, { ex.row_of("finder"), 0 })
						require("beast.libs.explorer.actions.set_root").run()
						require("beast.libs.explorer.actions.navigate_up").run()
						return ex.state.tree.root.path == ex.root .. "/lua/beast/libs"
					end)
				)
			end)

			t.it("stop twice is safe", function()
				t.eq(
					false,
					n.exec_lua(function()
						local ex = _G.ex
						ex.search.start()
						ex.search.stop()
						ex.search.stop()
						return ex.search.is_active()
					end)
				)
			end)

			t.it("closing the explorer ends search mode", function()
				t.eq(
					false,
					n.exec_lua(function()
						local ex = _G.ex
						ex.search.start()
						ex.explorer.close()
						return ex.search.is_active()
					end)
				)
			end)
		end)

		t.describe("keys with the finder available", function()
			for _, lhs in ipairs({ "/", "?", "<Esc><Esc>" }) do
				t.it(lhs .. " is mapped in the explorer", function()
					t.eq(
						true,
						n.exec_lua(function(l)
							return _G.ex.has_map(_G.ex.state.view.buf, l)
						end, lhs)
					)
				end)
			end
		end)
	end)
end)
