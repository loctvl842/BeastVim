local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

local TOKEN = "a3f1c2d4e5f60718293a4b5c6d7e8f90"

t.describe("review identity", function()
	t.before_each(function()
		h.clear()
		-- Keep every file this spec writes out of the real state and ~/.claude dirs.
		n.exec_lua(function()
			local root = vim.fn.tempname()
			vim.fn.mkdir(root, "p")
			vim.env.XDG_STATE_HOME = root .. "/state"
			vim.env.CLAUDE_CONFIG_DIR = root .. "/claude"
			_G.root = root
			_G.Toast = function() end
		end)
	end)

	t.after_each(function()
		n.exec_lua(function()
			require("beast.libs.review").stop()
			vim.fn.delete(_G.root, "rf")
		end)
	end)

	t.describe("store", function()
		t.it("has nothing saved yet", function()
			t.eq(
				nil,
				n.exec_lua(function()
					return require("beast.libs.review.server.identity").load("/work/a")
				end)
			)
		end)

		t.it("round-trips a saved identity", function()
			t.eq(
				{ saved = true, loaded = { port = 51234, token = TOKEN } },
				n.exec_lua(function(token)
					local identity = require("beast.libs.review.server.identity")
					local saved = identity.save("/work/a", 51234, token)
					return { saved = saved and true or false, loaded = identity.load("/work/a") }
				end, TOKEN)
			)
		end)

		t.it("keeps directories separate", function()
			t.eq(
				nil,
				n.exec_lua(function(token)
					local identity = require("beast.libs.review.server.identity")
					identity.save("/work/a", 51234, token)
					return identity.load("/work/b")
				end, TOKEN)
			)
		end)

		t.it("writes the file with mode 0600", function()
			t.eq(
				tonumber("600", 8),
				n.exec_lua(function(token)
					local identity = require("beast.libs.review.server.identity")
					identity.save("/work/a", 51234, token)
					return vim.uv.fs_stat(identity.path("/work/a")).mode % 512
				end, TOKEN)
			)
		end)

		for name, spec in pairs({
			garbage = { raw = "not json" },
			bad_port = { port = 70000 },
			fractional_port = { port = 80.5 },
			short_token = { token = "abc" },
			non_hex_token = { token = ("z"):rep(32) },
		}) do
			t.it("rejects " .. name, function()
				t.eq(
					nil,
					n.exec_lua(function(token, s)
						local identity = require("beast.libs.review.server.identity")
						local body = s.raw or vim.json.encode({ port = s.port or 8000, token = s.token or token })
						local path = identity.path("/work/c")
						vim.fn.mkdir(vim.fs.dirname(path), "p")
						local f = assert(io.open(path, "wb"))
						f:write(body)
						f:close()
						return identity.load("/work/c")
					end, TOKEN, spec)
				)
			end)
		end
	end)

	t.describe("Review.start", function()
		t.it("comes back on the same address after a restart", function()
			local r = n.exec_lua(function()
				local identity = require("beast.libs.review.server.identity")
				local lockfile = require("beast.libs.review.server.lockfile")
				local review = require("beast.libs.review")
				local function lock_token(port)
					local f = assert(io.open(lockfile.path(port), "rb"))
					local data = vim.json.decode(f:read("*a"))
					f:close()
					return data.authToken
				end

				local out = { first_started = review.start() }
				local first = review.status()
				local token = lock_token(first.port)
				out.identity_saved = vim.deep_equal(identity.load(vim.fn.getcwd()), { port = first.port, token = token })
				review.stop()
				out.lock_removed = vim.uv.fs_stat(lockfile.path(first.port)) == nil
				out.second_started = review.start()
				local second = review.status()
				out.same_port = second.port == first.port
				out.same_token = lock_token(second.port) == token
				return out
			end)
			t.eq({
				first_started = true,
				identity_saved = true,
				lock_removed = true,
				second_started = true,
				same_port = true,
				same_token = true,
			}, r)
		end)

		t.it("serves a fresh address when the saved port is taken, keeping the saved identity", function()
			local r = n.exec_lua(function()
				local identity = require("beast.libs.review.server.identity")
				local lockfile = require("beast.libs.review.server.lockfile")
				local review = require("beast.libs.review")
				local function lock_token(port)
					local f = assert(io.open(lockfile.path(port), "rb"))
					local data = vim.json.decode(f:read("*a"))
					f:close()
					return data.authToken
				end

				assert(review.start())
				review.stop()
				local saved = assert(identity.load(vim.fn.getcwd()))
				local squatter = vim.uv.new_tcp()
				assert(squatter:bind("127.0.0.1", saved.port))
				squatter:listen(1, function() end)

				local out = { started = review.start() }
				local s = review.status()
				out.different_port = s.port ~= saved.port
				out.fresh_token = lock_token(s.port) ~= saved.token
				out.identity_untouched = vim.deep_equal(identity.load(vim.fn.getcwd()), saved)
				review.stop()
				squatter:close()
				return out
			end)
			t.eq({ started = true, different_port = true, fresh_token = true, identity_untouched = true }, r)
		end)
	end)
end)
