local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- What the other libs do when bigfile says a buffer is big (docs/dev-specs/bigfile-init.md).
t.describe("bigfile guards", function()
	t.before_each(function()
		h.clear()
		n.exec_lua(function()
			vim.cmd("filetype on")
			_G.Toast = function() end
			_G.Bigfile = require("beast.libs.bigfile")
			Bigfile.setup({ size = 1000 })
			_G.dir = vim.fn.tempname()
			vim.fn.mkdir(dir, "p")
			---Open a Lua file of `count` lines (about 20 bytes each) in the current window.
			---@param name string
			---@param count integer
			---@return integer buf
			_G.open = function(name, count)
				local lines = {}
				for i = 1, count do
					lines[i] = "local v" .. i .. " = " .. i
				end
				local path = dir .. "/" .. name
				vim.fn.writefile(lines, path)
				vim.cmd.edit(vim.fn.fnameescape(path))
				return vim.api.nvim_get_current_buf()
			end
		end)
	end)

	t.describe("treesitter", function()
		t.before_each(function()
			n.exec_lua(function()
				local ts = require("beast.libs.treesitter")
				ts.setup({})
				ts.enable()
			end)
		end)

		t.it("starts highlighting for a small buffer", function()
			t.eq(
				true,
				n.exec_lua(function()
					local buf = open("small.lua", 3)
					return vim.treesitter.highlighter.active[buf] ~= nil
				end)
			)
		end)

		t.it("does not start highlighting for a big buffer", function()
			t.eq(
				false,
				n.exec_lua(function()
					local buf = open("big.lua", 200)
					return vim.treesitter.highlighter.active[buf] ~= nil
				end)
			)
		end)

		t.it("keeps highlighting in a small buffer opened after a big one", function()
			t.eq(
				{ false, true },
				n.exec_lua(function()
					local big = open("big.lua", 200)
					local small = open("small.lua", 3)
					return { vim.treesitter.highlighter.active[big] ~= nil, vim.treesitter.highlighter.active[small] ~= nil }
				end)
			)
		end)

		t.it("highlights a big buffer when treesitter is left on for big files", function()
			t.eq(
				true,
				n.exec_lua(function()
					Bigfile.setup({ size = 1000, disable = { treesitter = false } })
					local buf = open("big.lua", 200)
					return vim.treesitter.highlighter.active[buf] ~= nil
				end)
			)
		end)
	end)

	t.describe("lsp", function()
		t.before_each(function()
			n.exec_lua(function()
				_G.Icon = require("beast.icon")
				_G.Key = Util.mod("beast.libs.key")
				require("beast.libs.lsp").setup({})
				---A server that answers `initialize` and nothing else.
				_G.fake_cmd = function()
					return {
						request = function(method, _, cb)
							if method == "initialize" then
								cb(nil, { capabilities = {} })
							end
							return true, 1
						end,
						notify = function()
							return true
						end,
						is_closing = function()
							return false
						end,
						terminate = function() end,
					}
				end
			end)
		end)

		---Does the registered server's root_dir call `on_dir` for a file of `count` lines?
		---@param opts table extra fields for `register`
		---@param count integer
		---@return boolean
		local function starts(opts, count)
			return n.exec_lua(function(o, c)
				o.cmd = _G.fake_cmd
				if o.custom_root then
					o.custom_root = nil
					o.root_dir = function(_, on_dir)
						on_dir("/x")
					end
				end
				o.filetypes = { "lua" }
				require("beast.libs.lsp").register("fake_big", o)
				local buf = open("f.lua", c)
				local called = false
				vim.lsp.config.fake_big.root_dir(buf, function()
					called = true
				end)
				return called
			end, opts, count)
		end

		t.it("does not start a server for a big buffer", function()
			t.eq(false, starts({ root_markers = { ".git" } }, 200))
		end)

		t.it("starts a server for a small buffer", function()
			t.eq(true, starts({ root_markers = { ".git" } }, 3))
		end)

		t.it("keeps a custom root_dir for a small buffer", function()
			t.eq(true, starts({ custom_root = true }, 3))
		end)

		t.it("does not start a server with a static or absent root_dir for a big buffer", function()
			t.eq({ false, false }, { starts({ root_dir = "/x" }, 200), starts({}, 200) })
		end)

		t.it("detaches a client that attached to a big buffer, and only that one", function()
			t.eq(
				{ 0, 1 },
				n.exec_lua(function()
					local big = open("big.lua", 200)
					local small = open("small.lua", 3)
					for _, buf in ipairs({ big, small }) do
						vim.lsp.start({ name = "fake_bs", cmd = _G.fake_cmd, root_dir = dir }, { bufnr = buf })
					end
					vim.wait(1000, function()
						return #vim.lsp.get_clients({ bufnr = small }) > 0
					end)
					vim.wait(100)
					return { #vim.lsp.get_clients({ bufnr = big }), #vim.lsp.get_clients({ bufnr = small }) }
				end)
			)
		end)
	end)

	t.describe("git", function()
		---Is the buffer attached to git after the async attach had time to finish?
		---@param count integer
		---@return boolean
		local function attached(count)
			return n.exec_lua(function(c)
				vim.fn.system({ "git", "-C", dir, "init", "-q" })
				vim.fn.system({ "git", "-C", dir, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init" })
				local buf = open("f.lua", c)
				local G = require("beast.libs.git")
				G.attach(buf)
				vim.wait(800, function()
					return G._get_state(buf) ~= nil
				end)
				return G._get_state(buf) ~= nil
			end, count)
		end

		t.it("attaches to a small buffer", function()
			t.eq(true, attached(3))
		end)

		t.it("does not attach to a big buffer", function()
			t.eq(false, attached(200))
		end)
	end)

	t.describe("breadcrumb symbols", function()
		---The symbol trail for a cursor inside a function of `count` filler lines.
		---@param count integer
		---@return integer
		local function trail_len(count)
			return n.exec_lua(function(c)
				local buf = open("f.lua", c)
				vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "local function outer()", "  return 1", "end" })
				vim.api.nvim_win_set_cursor(0, { 2, 2 })
				vim.treesitter.start(buf, "lua")
				return #require("beast.libs.breadcrumb.symbols").trail(buf, 0)
			end, count)
		end

		t.it("finds the enclosing function in a small buffer", function()
			t.eq(true, trail_len(3) > 0)
		end)

		t.it("has no trail in a big buffer", function()
			t.eq(0, trail_len(200))
		end)
	end)
end)
