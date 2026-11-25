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
end)
