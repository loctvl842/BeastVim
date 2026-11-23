local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Parsers installed by the real config (NVIM_APPNAME=BeastVim) live outside the harness runtimepath,
-- and the harness redirects stdpath("data").
local SITE = vim.env.HOME .. "/.local/share/BeastVim/site"

---Statusline format string -> visible text.
local function plain(fmt)
	return (fmt:gsub("%%#%w+#", ""):gsub("%%%*", ""))
end

t.describe("breadcrumb symbols", function()
	t.before_each(h.clear)

	t.describe("filepath.render", function()
		-- `_G.bc_render(width, symbols, modified)` renders BUFNAME (under the real project root).
		t.before_each(function()
			n.exec_lua(function()
				local filepath = require("beast.libs.breadcrumb.filepath")
				local buf = vim.api.nvim_create_buf(false, false)
				local bufname = Util.root() .. "/lua/beast/libs/breadcrumb/init.lua"
				_G.bc_render = function(width, symbols, modified)
					vim.bo[buf].modified = modified or false
					return filepath.render({ bufnr = buf, bufname = bufname, width = width }, "  ", "+", symbols)
				end
			end)
		end)

		---@param width integer
		---@param symbols? table[]
		---@param modified? boolean
		---@return string
		local function render(width, symbols, modified)
			return n.exec_lua(function(w, s, m)
				return _G.bc_render(w, s or nil, m)
			end, width, symbols or false, modified or false)
		end

		local chain = {
			{ name = "M", kind = "Module" },
			{ name = "setup", kind = "Function" },
			{ name = "ensure_autocmds", kind = "Function" },
		}
		local function icon_fn()
			return n.exec_lua(function()
				return vim.trim(require("beast.icon").kinds.Function)
			end)
		end

		-- Output captured from the implementation before symbols existed
		local parity = {
			{
				modified = false,
				width = 80,
				expected = "%#BeastBcDir#lua%*%#BeastBcSep#  %*%#BeastBcDir#beast%*%#BeastBcSep#  %*%#BeastBcDir#libs%*%#BeastBcSep#  %*%#BeastBcDir#breadcrumb%*%#BeastBcSep#  %*%#BeastBcFile#init.lua%*",
			},
			{
				modified = false,
				width = 30,
				expected = "%#BeastBcSep#…%*%#BeastBcSep#  %*%#BeastBcDir#libs%*%#BeastBcSep#  %*%#BeastBcDir#breadcrumb%*%#BeastBcSep#  %*%#BeastBcFile#init.lua%*",
			},
			{ modified = false, width = 20, expected = "%#BeastBcSep#…%*%#BeastBcFile#init.lua%*" },
			{
				modified = true,
				width = 80,
				expected = "%#BeastBcDir#lua%*%#BeastBcSep#  %*%#BeastBcDir#beast%*%#BeastBcSep#  %*%#BeastBcDir#libs%*%#BeastBcSep#  %*%#BeastBcDir#breadcrumb%*%#BeastBcSep#  %*%#BeastBcFile#init.lua%*%#BeastBcModified#+%*",
			},
			{ modified = true, width = 24, expected = "%#BeastBcSep#…%*%#BeastBcFile#init.lua%*%#BeastBcModified#+%*" },
			{ modified = true, width = 12, expected = "%#BeastBcSep#…%*%#BeastBcFile#init.lua%*%#BeastBcModified#+%*" },
		}
		for _, c in ipairs(parity) do
			t.it(("no symbols, width %d, modified=%s matches old output"):format(c.width, tostring(c.modified)), function()
				t.eq(c.expected, render(c.width, nil, c.modified))
			end)
		end

		t.it("wide: path, file and every symbol in order", function()
			local full = plain(render(200, chain))
			t.eq(true, full:find("breadcrumb  init.lua  .-M  .-setup  .-ensure_autocmds") ~= nil, full)
		end)

		t.it("symbol segment carries the kind icon", function()
			t.eq(true, plain(render(200, chain)):find(icon_fn() .. " setup", 1, true) ~= nil)
		end)

		t.it("symbol uses its family highlight", function()
			t.eq(true, render(200, chain):find("%#BeastBcSymCallable#" .. icon_fn(), 1, true) ~= nil)
		end)

		t.it("empty-name symbols are skipped", function()
			local out = plain(render(200, { { name = "", kind = "Function" }, { name = "x", kind = "Function" } }))
			t.eq(true, out:find("init.lua  .- x$") ~= nil, out)
		end)

		t.it("modified marker is last, after the final symbol", function()
			t.eq("+", plain(render(200, chain, true)):sub(-1))
		end)

		t.it("clean buffer has no marker", function()
			t.eq(true, plain(render(200, chain, false)):find("+", 1, true) == nil)
		end)

		t.it("narrow: dirs collapse first, symbols stay whole", function()
			-- tail (file + all symbols) still fits
			local tail_only = plain(render(200, chain)):gsub("^.-init.lua", "init.lua")
			local w = 1 + vim.fn.strdisplaywidth(tail_only) + 3
			local out = plain(render(w, chain))
			t.eq(1, out:find("…", 1, true))
			t.eq(true, out:find("setup", 1, true) ~= nil, out)
			t.eq(true, out:find("ensure_autocmds", 1, true) ~= nil, out)
		end)

		t.it("narrow: outer dir is gone", function()
			local tail_only = plain(render(200, chain)):gsub("^.-init.lua", "init.lua")
			local out = plain(render(1 + vim.fn.strdisplaywidth(tail_only) + 3, chain))
			t.eq(true, out:find("breadcrumb", 1, true) == nil, out)
		end)

		t.it("narrower: file and innermost symbol kept, outer symbols collapse to an ellipsis", function()
			local out = plain(render(36, chain))
			t.eq(true, out:find("init.lua", 1, true) ~= nil, out)
			t.eq(true, out:find("ensure_autocmds", 1, true) ~= nil, out)
			t.eq(true, out:find("setup", 1, true) == nil, out)
			t.eq(true, out:find("init.lua  …", 1, true) ~= nil, out)
		end)

		t.it("narrower: marker still last", function()
			local out = plain(render(36, chain, true))
			t.eq("+", out:sub(-1))
			t.eq(true, out:find("ensure_autocmds", 1, true) ~= nil, out)
		end)

		t.it("single symbol is never dropped", function()
			local out = plain(render(10, { { name = "only_symbol", kind = "Function" } }))
			t.eq(true, out:find("only_symbol", 1, true) ~= nil, out)
		end)
	end)

	t.describe("symbols.lsp", function()
		-- Child-side fixtures: `_G.bc` holds the lsp module, helpers and the stubbed request queue.
		t.before_each(function()
			n.exec_lua(function()
				local function rng(sr, sc, er, ec)
					return { start = { line = sr, character = sc }, ["end"] = { line = er, character = ec } }
				end
				local lsp = require("beast.libs.breadcrumb.symbols.lsp")
				-- class Server (0-9) { method start (1-4) { inner (2-3) } ; method stop (6-8) }
				local doc_symbols = {
					{
						name = "Server",
						kind = 5,
						range = rng(0, 0, 9, 3),
						selectionRange = rng(0, 6, 0, 12),
						children = {
							{ name = "stop", kind = 6, range = rng(6, 2, 8, 5), selectionRange = rng(6, 2, 6, 6) },
							{
								name = "start",
								kind = 6,
								range = rng(1, 2, 4, 5),
								selectionRange = rng(1, 2, 1, 7),
								children = {
									{ name = "inner", kind = 12, range = rng(2, 4, 3, 7), selectionRange = rng(2, 4, 2, 9) },
								},
							},
						},
					},
				}
				local function names(chain)
					return table.concat(
						vim.tbl_map(function(s)
							return s.name
						end, chain),
						">"
					)
				end
				local lbuf = vim.api.nvim_create_buf(false, false)
				vim.api.nvim_buf_set_lines(lbuf, 0, -1, false, { "class Server {", "  start() {", "    inner", "  }", "}" })
				local pending = {}
				-- Stub only the server round trip, so replies can be ordered by hand.
				vim.lsp.get_clients = function()
					return { { id = 1 } }
				end
				vim.lsp.get_client_by_id = function()
					return { offset_encoding = "utf-16" }
				end
				vim.lsp.buf_request_all = function(_, _, _, cb)
					pending[#pending + 1] = cb
				end
				local bc = { lsp = lsp, rng = rng, doc_symbols = doc_symbols, names = names, buf = lbuf, changed = 0 }
				lsp.on_change = function()
					bc.changed = bc.changed + 1
				end
				function bc.reply(i, res)
					pending[i](res)
				end
				function bc.ok(result)
					return { [1] = { result = result } }
				end
				function bc.trail(row, col)
					local tr = lsp.trail(lbuf, row, col)
					return tr and names(tr) or "nil"
				end
				_G.bc = bc
			end)
		end)

		---Names of the chain at (row, col) of the normalized document-symbol tree.
		local function find(row, col)
			return n.exec_lua(function(r, c)
				local tree = _G.bc.lsp.normalize(_G.bc.doc_symbols)
				return _G.bc.names(_G.bc.lsp.find(tree, r, c))
			end, row, col)
		end

		t.describe("normalize and find", function()
			t.it("kind number maps to Icon.kinds key", function()
				t.eq(
					"Class",
					n.exec_lua(function()
						return _G.bc.lsp.normalize(_G.bc.doc_symbols)[1].kind
					end)
				)
			end)
			t.it("siblings are sorted by start", function()
				t.eq(
					"start",
					n.exec_lua(function()
						return _G.bc.lsp.normalize(_G.bc.doc_symbols)[1].children[1].name
					end)
				)
			end)
			t.it("nested cursor gives the full chain", function()
				t.eq("Server>start>inner", find(2, 5))
			end)
			t.it("cursor in method body, outside inner", function()
				t.eq("Server>start", find(1, 3))
			end)
			t.it("cursor on a header line counts as inside", function()
				t.eq("Server>stop", find(6, 2))
			end)
			t.it("cursor between siblings stays in the parent", function()
				t.eq("Server", find(5, 0))
			end)
			t.it("cursor after the end of a symbol is outside", function()
				t.eq("", find(9, 3))
			end)
			t.it("cursor before a symbol on its first line is outside", function()
				t.eq("Server>start", find(2, 3))
			end)
			t.it("empty tree gives an empty chain", function()
				t.eq(
					"",
					n.exec_lua(function()
						return _G.bc.names(_G.bc.lsp.find({}, 0, 0))
					end)
				)
			end)
		end)

		t.describe("flat SymbolInformation", function()
			-- hierarchy rebuilt from ranges, input order irrelevant
			local function flat_find(row, col)
				return n.exec_lua(function(r, c)
					local rng = _G.bc.rng
					local flat = _G.bc.lsp.normalize({
						{ name = "inner", kind = 12, location = { uri = "file:///x", range = rng(2, 4, 3, 7) } },
						{ name = "start", kind = 6, location = { uri = "file:///x", range = rng(1, 2, 4, 5) } },
						{ name = "Server", kind = 5, location = { uri = "file:///x", range = rng(0, 0, 9, 3) } },
						{ name = "later", kind = 12, location = { uri = "file:///x", range = rng(11, 0, 12, 3) } },
					})
					return _G.bc.names(_G.bc.lsp.find(flat, r, c))
				end, row, col)
			end
			t.it("nested by range containment", function()
				t.eq("Server>start>inner", flat_find(2, 5))
			end)
			t.it("second root", function()
				t.eq("later", flat_find(11, 1))
			end)
		end)

		t.describe("refresh", function()
			t.it("has nothing before any reply", function()
				t.eq(
					"nil",
					n.exec_lua(function()
						return _G.bc.trail(2, 4)
					end)
				)
			end)

			t.it("applies the newest reply and ignores an older one arriving late", function()
				t.eq(
					{ "Server>start>inner", "Server>start>inner", 1 },
					n.exec_lua(function()
						local bc = _G.bc
						bc.lsp.refresh(bc.buf)
						bc.lsp.refresh(bc.buf)
						bc.reply(2, bc.ok(bc.doc_symbols))
						local newest = bc.trail(2, 5)
						bc.reply(1, bc.ok({ { name = "Stale", kind = 12, range = bc.rng(0, 0, 9, 0), selectionRange = bc.rng(0, 0, 0, 1) } }))
						return { newest, bc.trail(2, 5), bc.changed }
					end)
				)
			end)

			t.it("an errored reply keeps the previous tree", function()
				t.eq(
					"Server>start>inner",
					n.exec_lua(function()
						local bc = _G.bc
						bc.lsp.refresh(bc.buf)
						bc.reply(1, bc.ok(bc.doc_symbols))
						bc.lsp.refresh(bc.buf)
						bc.reply(2, { [1] = { err = { code = -32801 } } })
						return bc.trail(2, 5)
					end)
				)
			end)

			t.it("a successful empty reply clears the tree, and it comes back after a later reply", function()
				t.eq(
					{ "nil", "Server>start>inner" },
					n.exec_lua(function()
						local bc = _G.bc
						bc.lsp.refresh(bc.buf)
						bc.reply(1, bc.ok(bc.doc_symbols))
						bc.lsp.refresh(bc.buf)
						bc.reply(2, bc.ok({}))
						local cleared = bc.trail(2, 5)
						bc.lsp.refresh(bc.buf)
						bc.reply(3, bc.ok(bc.doc_symbols))
						return { cleared, bc.trail(2, 5) }
					end)
				)
			end)

			t.it("converts byte columns to the server encoding", function()
				-- "é" is 2 bytes but 1 UTF-16 unit: byte col 5 is UTF-16 col 4 (start of `function`)
				t.eq(
					{ "f", "" },
					n.exec_lua(function()
						local bc = _G.bc
						vim.api.nvim_buf_set_lines(bc.buf, 0, -1, false, { "é = function() return 1 end" })
						bc.lsp.refresh(bc.buf)
						bc.reply(1, bc.ok({ { name = "f", kind = 12, range = bc.rng(0, 4, 0, 27), selectionRange = bc.rng(0, 4, 0, 5) } }))
						return { bc.trail(0, 5), bc.trail(0, 3) }
					end)
				)
			end)

			t.it("clear forgets the buffer", function()
				t.eq(
					"nil",
					n.exec_lua(function()
						local bc = _G.bc
						bc.lsp.refresh(bc.buf)
						bc.reply(1, bc.ok(bc.doc_symbols))
						bc.lsp.clear(bc.buf)
						return bc.trail(0, 5)
					end)
				)
			end)
		end)
	end)

	t.describe("symbols.treesitter", function()
		t.before_each(function()
			n.exec_lua(function(site)
				vim.opt.runtimepath:append(site)
				vim.treesitter.language.register("tsx", "typescriptreact") -- the real config does this in its treesitter lib
				_G.ts_trail = function(ft, lines, row, col)
					local lang = vim.treesitter.language.get_lang(ft)
					local loaded = lang and select(2, pcall(vim.treesitter.language.add, lang))
					if not loaded then
						return { missing = true }
					end
					local b = vim.api.nvim_create_buf(false, false)
					vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
					vim.bo[b].filetype = ft
					local tr = require("beast.libs.breadcrumb.symbols.treesitter").trail(b, row, col)
					return {
						chain = tr and table.concat(
							vim.tbl_map(function(s)
								return s.name
							end, tr),
							">"
						) or "nil",
					}
				end
			end, SITE)
		end)

		---@param ft string
		---@param lines string[]
		---@param cases { [1]: integer, [2]: integer, [3]: string }[] row, col, expected chain
		local function ts_cases(ft, lines, cases)
			for _, c in ipairs(cases) do
				t.it(("%s: (%d,%d) -> %q"):format(ft, c[1], c[2], c[3]), function()
					local r = n.exec_lua(function(f, l, row, col)
						return _G.ts_trail(f, l, row, col)
					end, ft, lines, c[1], c[2])
					if r.missing then
						t.pending(ft .. ": no parser installed")
					end
					t.eq(c[3], r.chain)
				end)
			end
		end

		ts_cases("lua", {
			"local M = {}",
			"function M.setup(opts)",
			"  local f = function()",
			"    return 1",
			"  end",
			'  vim.api.nvim_create_autocmd("X", { callback = function()',
			"    print(1)",
			"  end })",
			"end",
			"function M:method() end",
		}, { { 0, 0, "" }, { 3, 6, "M.setup>f" }, { 6, 6, "M.setup>callback" }, { 9, 21, "M:method" } })

		ts_cases("python", {
			"class Server:",
			"    def start(self):",
			"        def inner():",
			"            pass",
			"async def run():",
			"    pass",
		}, { { 0, 0, "Server" }, { 3, 12, "Server>start>inner" }, { 5, 4, "run" } })

		ts_cases("javascript", {
			"class Server {",
			"  start() {",
			"    const f = () => 1;",
			"  }",
			"}",
			"function run() {}",
			"const arrow = () => {};",
		}, { { 2, 20, "Server>start>f" }, { 5, 16, "run" }, { 6, 21, "arrow" } })

		ts_cases("typescript", {
			"interface Cfg { a: number }",
			"enum Color { Red }",
			"const o = { key: function() { return 1 } }",
		}, { { 0, 20, "Cfg" }, { 1, 14, "Color" }, { 2, 35, "key" } })

		ts_cases("typescriptreact", { "const C = () => <div/>;" }, { { 0, 20, "C" } })

		ts_cases("c", {
			"struct S { int a; };",
			"int main(void) {",
			"  return 0;",
			"}",
		}, { { 0, 13, "S" }, { 2, 4, "main" } })

		ts_cases("cpp", {
			"namespace N {",
			"class C { void m() { int x; } };",
			"void C::f() { int y; }",
			"}",
		}, { { 1, 22, "N>C>m" }, { 2, 15, "N>C::f" } })

		ts_cases("markdown", {
			"# Install",
			"text",
			"## Linux",
			"more",
			"",
			"```lua",
			"local x = 1",
			"```",
			"# Other",
		}, { { 1, 0, "Install" }, { 3, 1, "Install>Linux" }, { 6, 2, "Install>Linux" }, { 8, 2, "Other" } })

		ts_cases("xml", {
			'<?xml version="1.0" encoding="UTF-8"?>',
			'<project name="demo">',
			"  <dependencies>",
			"    <dependency>",
			"      <groupId>org.example</groupId>",
			"    </dependency>",
			"  </dependencies>",
			"  <build><plugins/></build>",
			"</project>",
		}, {
			{ 0, 5, "" },
			{ 1, 3, "project" },
			{ 4, 14, "project>dependencies>dependency>groupId" },
			{ 5, 6, "project>dependencies>dependency" },
			{ 7, 12, "project>build>plugins" },
		})

		t.it("unknown language: source has nothing", function()
			local b = n.exec_lua(function()
				local b = vim.api.nvim_create_buf(false, false)
				vim.api.nvim_buf_set_lines(b, 0, -1, false, { "plain" })
				vim.bo[b].filetype = "text"
				return require("beast.libs.breadcrumb.symbols.treesitter").trail(b, 0, 0) == nil
			end)
			t.eq(true, b)
		end)
	end)

	t.describe("source selection", function()
		-- The server wins; the trail is never a mix of both sources.
		t.before_each(function()
			n.exec_lua(function(site)
				vim.opt.runtimepath:append(site)
				local ok = pcall(vim.treesitter.language.add, "lua")
				local sb = vim.api.nvim_create_buf(false, false)
				vim.api.nvim_buf_set_lines(sb, 0, -1, false, { "local M = {}", "function M.setup()", "  return 1", "end" })
				vim.bo[sb].filetype = "lua"
				vim.api.nvim_win_set_buf(0, sb)
				vim.api.nvim_win_set_cursor(0, { 3, 4 })
				local sym = require("beast.libs.breadcrumb.symbols")
				local replies = {}
				_G.sel = {
					ok = ok,
					sym = sym,
					buf = sb,
					replies = replies,
					names = function(chain)
						return table.concat(
							vim.tbl_map(function(s)
								return s.name
							end, chain),
							">"
						)
					end,
					serve = function()
						vim.lsp.get_clients = function()
							return { { id = 1 } }
						end
						vim.lsp.get_client_by_id = function()
							return { offset_encoding = "utf-16" }
						end
						vim.lsp.buf_request_all = function(_, _, _, cb)
							replies[#replies + 1] = cb
						end
						sym.refresh(sb)
						local function rng(sr, sc, er, ec)
							return { start = { line = sr, character = sc }, ["end"] = { line = er, character = ec } }
						end
						replies[1]({
							[1] = {
								result = {
									{
										name = "ServerSaysSetup",
										kind = 12,
										range = rng(1, 0, 3, 3),
										selectionRange = rng(1, 9, 1, 14),
									},
								},
							},
						})
					end,
				}
			end, SITE)
			if not n.exec_lua("return _G.sel.ok") then
				t.pending("lua parser unavailable")
			end
		end)

		t.it("no server: trail comes from the syntax tree", function()
			t.eq(
				"M.setup",
				n.exec_lua(function()
					return _G.sel.names(_G.sel.sym.trail(_G.sel.buf, 0))
				end)
			)
		end)

		t.it("server answered: its symbols are used, not the syntax tree's", function()
			t.eq(
				"ServerSaysSetup",
				n.exec_lua(function()
					_G.sel.serve()
					return _G.sel.names(_G.sel.sym.trail(_G.sel.buf, 0))
				end)
			)
		end)

		t.it("server answered, cursor outside every symbol: stays empty", function()
			t.eq(
				"",
				n.exec_lua(function()
					_G.sel.serve()
					vim.api.nvim_win_set_cursor(0, { 1, 0 })
					return _G.sel.names(_G.sel.sym.trail(_G.sel.buf, 0))
				end)
			)
		end)

		t.it("server gone: syntax tree again", function()
			-- cursor on line 1 sits outside `M.setup`, so the syntax tree answers with an empty chain
			t.eq(
				"",
				n.exec_lua(function()
					_G.sel.serve()
					vim.api.nvim_win_set_cursor(0, { 1, 0 })
					_G.sel.sym.clear(_G.sel.buf)
					return _G.sel.names(_G.sel.sym.trail(_G.sel.buf, 0))
				end)
			)
		end)
	end)
end)
