local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

t.describe("packer failures", function()
	t.before_each(function()
		h.clear()
		-- Isolated state/data dirs so the test never touches the real ones.
		n.exec_lua(function()
			local root = vim.fn.tempname()
			vim.env.XDG_STATE_HOME = root .. "/state"
			vim.env.XDG_DATA_HOME = root .. "/data"
			_G.root = root
			_G.file = vim.fn.stdpath("state") .. "/beast/packer-failures.json"
			--- Fresh module instance, as on a new nvim start.
			_G.fresh = function()
				package.loaded["beast.libs.packer.failures"] = nil
				return require("beast.libs.packer.failures")
			end
			_G.write_raw = function(text)
				vim.fn.mkdir(vim.fn.fnamemodify(_G.file, ":h"), "p")
				local f = assert(io.open(_G.file, "w"))
				f:write(text)
				f:close()
			end
		end)
	end)

	t.after_each(function()
		n.exec_lua("vim.fn.delete(_G.root, 'rf')")
	end)

	t.describe("record", function()
		t.it("persists across restarts", function()
			t.eq(
				{ found = true, src = "https://github.com/x/json", reason = "remote: Repository not found." },
				n.exec_lua(function()
					_G.fresh().record("json", "https://github.com/x/json", "remote: Repository not found.")
					local rec = _G.fresh().list().json
					return { found = rec ~= nil, src = rec and rec.src, reason = rec and rec.reason }
				end)
			)
		end)

		t.it("clear persists", function()
			t.eq(
				true,
				n.exec_lua(function()
					_G.fresh().record("json", "s", "r")
					_G.fresh().clear("json")
					return _G.fresh().list().json == nil
				end)
			)
		end)
	end)

	t.describe("missing or corrupt file", function()
		---@param raw? string nil removes the file
		local function list_is_empty(raw)
			return n.exec_lua(function(r)
				if r then
					_G.write_raw(r)
				else
					vim.fn.delete(_G.file)
				end
				return next(_G.fresh().list()) == nil
			end, raw)
		end

		t.it("missing file is empty", function()
			t.eq(true, list_is_empty(nil))
		end)

		t.it("corrupt file is empty", function()
			t.eq(true, list_is_empty("{not json"))
		end)

		t.it("non-table json is empty", function()
			t.eq(true, list_is_empty('"just a string"'))
		end)

		t.it("recording after a corrupt file works", function()
			t.eq(
				true,
				n.exec_lua(function()
					_G.write_raw("{not json")
					_G.fresh().record("a", "s", "r")
					return _G.fresh().list().a ~= nil
				end)
			)
		end)
	end)

	t.describe("retry window", function()
		t.it("blocks inside the window, not with a zero window or unknown plugin", function()
			t.eq(
				{ true, false, false },
				n.exec_lua(function()
					local failures = _G.fresh()
					failures.record("json", "s", "r")
					return { failures.is_blocked("json", 24), failures.is_blocked("json", 0), failures.is_blocked("nope", 24) }
				end)
			)
		end)

		t.it("is not blocked after the window expires", function()
			t.eq(
				false,
				n.exec_lua(function()
					_G.write_raw(vim.json.encode({ json = { src = "s", reason = "r", at = os.time() - 25 * 3600 } }))
					return _G.fresh().is_blocked("json", 24)
				end)
			)
		end)

		t.it("is still blocked just inside the window", function()
			t.eq(
				true,
				n.exec_lua(function()
					_G.write_raw(vim.json.encode({ json = { src = "s", reason = "r", at = os.time() - 23 * 3600 } }))
					return _G.fresh().is_blocked("json", 24)
				end)
			)
		end)
	end)

	t.describe("prune", function()
		t.it("drops records that no longer apply", function()
			t.eq(
				{ removed = false, moved = false, installed = false, kept = true },
				n.exec_lua(function()
					local failures = _G.fresh()
					failures.record("removed", "s1", "r")
					failures.record("moved", "old-src", "r")
					failures.record("installed", "s3", "r")
					failures.record("kept", "s4", "r")
					vim.fn.mkdir(vim.fn.stdpath("data") .. "/site/pack/core/opt/installed", "p")
					failures.prune({
						{ name = "moved", src = "new-src" },
						{ name = "installed", src = "s3" },
						{ name = "kept", src = "s4" },
					})
					local list = _G.fresh().list()
					return {
						removed = list.removed ~= nil,
						moved = list.moved ~= nil,
						installed = list.installed ~= nil,
						kept = list.kept ~= nil,
					}
				end)
			)
		end)
	end)

	t.describe("reason_for", function()
		---@param name string
		local function reason(name)
			return n.exec_lua(function(plugin)
				local err = table.concat({
					"vim.pack:",
					"",
					"`json`:",
					"/usr/share/nvim/runtime/lua/vim/pack.lua:251: remote: Repository not found.",
					"fatal: repository 'https://github.com/x/json/' not found",
					"",
					"`cpp`:",
					"/usr/share/nvim/runtime/lua/vim/pack.lua:251: Could not resolve host: github.com",
				}, "\n")
				return _G.fresh().reason_for(err, plugin)
			end, name)
		end

		t.it("parses the first plugin", function()
			t.eq("remote: Repository not found.", reason("json"))
		end)

		t.it("parses the second plugin", function()
			t.eq("Could not resolve host: github.com", reason("cpp"))
		end)

		t.it("falls back for an unknown plugin", function()
			t.eq("install failed", reason("other"))
		end)

		t.it("treats magic chars in the name literally", function()
			t.eq("install failed", reason("j.on"))
		end)
	end)
end)
