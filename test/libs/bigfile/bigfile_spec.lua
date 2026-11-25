local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

t.describe("bigfile", function()
	t.before_each(function()
		h.clear()
		n.exec_lua(function()
			_G.toasts = {}
			_G.Toast = function(msg, level, opts)
				table.insert(_G.toasts, { msg = msg, level = level, title = opts and opts.title })
			end
			_G.Bigfile = require("beast.libs.bigfile")
			Bigfile.setup({ size = 1000, line_length = 100 })
			_G.dir = vim.fn.tempname()
			vim.fn.mkdir(dir, "p")
			---Write `lines` to a file and open it.
			---@param name string
			---@param lines string[]
			---@return integer buf
			_G.open = function(name, lines)
				local path = dir .. "/" .. name
				vim.fn.writefile(lines, path)
				vim.cmd.edit(vim.fn.fnameescape(path))
				return vim.api.nvim_get_current_buf()
			end
		end)
	end)

	t.describe("is", function()
		t.it("is false for a small file", function()
			t.eq(
				false,
				n.exec_lua(function()
					return Bigfile.is(open("small.xml", { "<a/>", "<b/>" }))
				end)
			)
		end)

		t.it("is true for a file over the size limit", function()
			t.eq(
				true,
				n.exec_lua(function()
					local lines = {}
					for i = 1, 200 do
						lines[i] = "<row id='" .. i .. "'/>"
					end
					return Bigfile.is(open("big.xml", lines))
				end)
			)
		end)

		t.it("is true for a small file with very long lines (minified)", function()
			t.eq(
				true,
				n.exec_lua(function()
					return Bigfile.is(open("min.js", { string.rep("x", 400), string.rep("y", 400) }))
				end)
			)
		end)

		t.it("is false for an empty file", function()
			t.eq(
				false,
				n.exec_lua(function()
					return Bigfile.is(open("empty.xml", {}))
				end)
			)
		end)

		t.it("is false for a file that is not on disk", function()
			t.eq(
				false,
				n.exec_lua(function()
					vim.cmd.edit(dir .. "/new.xml")
					return Bigfile.is(0)
				end)
			)
		end)

		t.it("is false for a non-file buffer", function()
			t.eq(
				false,
				n.exec_lua(function()
					local buf = vim.api.nvim_create_buf(false, true)
					vim.api.nvim_buf_set_lines(buf, 0, -1, false, { string.rep("x", 5000) })
					return Bigfile.is(buf)
				end)
			)
		end)

		t.it("is false for a buffer that is not loaded, and does not remember it", function()
			t.eq(
				{ false, true },
				n.exec_lua(function()
					local path = dir .. "/lazy.js"
					vim.fn.writefile({ string.rep("x", 5000) }, path)
					local buf = vim.fn.bufadd(path)
					local before = Bigfile.is(buf)
					vim.fn.bufload(buf)
					return { before, Bigfile.is(buf) }
				end)
			)
		end)

		t.it("is false for everything when enabled = false", function()
			t.eq(
				false,
				n.exec_lua(function()
					Bigfile.setup({ enabled = false, size = 1000 })
					return Bigfile.is(open("min.js", { string.rep("x", 5000) }))
				end)
			)
		end)

		t.it("keeps the verdict across :e", function()
			t.eq(
				{ true, true },
				n.exec_lua(function()
					local buf = open("min.js", { string.rep("x", 5000) })
					local first = Bigfile.is(buf)
					vim.cmd.edit()
					return { first, Bigfile.is(buf) }
				end)
			)
		end)

		t.it("decides again after the buffer is wiped and reopened", function()
			t.eq(
				{ true, false },
				n.exec_lua(function()
					local buf = open("grow.js", { string.rep("x", 5000) })
					local first = Bigfile.is(buf)
					vim.cmd.bwipeout({ bang = true })
					return { first, Bigfile.is(open("grow.js", { "tiny" })) }
				end)
			)
		end)

		t.it("leaves the filetype alone", function()
			t.eq(
				"xml",
				n.exec_lua(function()
					vim.cmd("filetype on")
					local buf = open("big.xml", { string.rep("<a/>", 500) })
					return vim.bo[buf].filetype
				end)
			)
		end)
	end)

	t.describe("disabled", function()
		t.it("follows the per-feature switch", function()
			t.eq(
				{ true, false, false },
				n.exec_lua(function()
					Bigfile.setup({ size = 1000, disable = { git = false } })
					local buf = open("min.js", { string.rep("x", 5000) })
					return { Bigfile.disabled(buf, "treesitter"), Bigfile.disabled(buf, "git"), Bigfile.disabled(buf, "nonsense") }
				end)
			)
		end)

		t.it("is false for a normal buffer", function()
			t.eq(
				false,
				n.exec_lua(function()
					return Bigfile.disabled(open("small.xml", { "<a/>" }), "treesitter")
				end)
			)
		end)
	end)

	t.describe("notice", function()
		t.it("toasts once per open with the name and size", function()
			local toasts = n.exec_lua(function()
				open("min.js", { string.rep("x", 5000) })
				vim.cmd.edit()
				vim.cmd.doautocmd("FileType")
				return _G.toasts
			end)
			t.eq(1, #toasts)
			t.eq("Big File", toasts[1].title)
			t.eq(true, toasts[1].msg:find("min.js", 1, true) ~= nil)
			t.eq(true, toasts[1].msg:find("5 KB", 1, true) ~= nil)
		end)

		t.it("toasts again when the file is reopened", function()
			t.eq(
				2,
				n.exec_lua(function()
					open("min.js", { string.rep("x", 5000) })
					vim.cmd.bwipeout({ bang = true })
					open("min.js", { string.rep("x", 5000) })
					return #_G.toasts
				end)
			)
		end)

		t.it("does not toast for a small file", function()
			t.eq(
				0,
				n.exec_lua(function()
					open("small.xml", { "<a/>" })
					return #_G.toasts
				end)
			)
		end)

		t.it("is silenced by notify = false but features stay off", function()
			t.eq(
				{ 0, true },
				n.exec_lua(function()
					Bigfile.setup({ size = 1000, notify = false })
					local buf = open("min.js", { string.rep("x", 5000) })
					return { #_G.toasts, Bigfile.disabled(buf, "treesitter") }
				end)
			)
		end)
	end)
end)
