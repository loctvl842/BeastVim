local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

local ENGINE = "beast.libs.finder.source.live_grep.engine"

t.describe("finder live_grep engine", function()
	t.before_each(h.clear)

	t.describe("extract.literal_runs", function()
		---@param query string
		local function runs(query)
			return n.exec_lua(function(q, engine)
				return require(engine .. ".extract").literal_runs(q)
			end, query, ENGINE)
		end

		t.it("keeps a plain literal whole", function()
			t.eq({ "error" }, runs("error"))
		end)

		t.it("drops an escaped metachar but keeps the run before it", function()
			t.eq({ "require" }, runs("require\\("))
		end)

		t.it("splits on dots and parens", function()
			t.eq({ "a", "b" }, runs("a.b"))
			t.eq({ "foo", "bar" }, runs("foo(bar)"))
		end)

		t.it("yields nothing for a pure regex", function()
			t.eq({}, runs("\\d+"))
		end)
	end)

	t.describe("extract.keys", function()
		t.it("only runs of 2+ bytes contribute", function()
			t.eq(
				{ true, false, false },
				n.exec_lua(function(engine)
					local extract = require(engine .. ".extract")
					return { #extract.keys("error") > 0, #extract.keys("a.b") > 0, #extract.keys("(.)") > 0 }
				end, ENGINE)
			)
		end)

		t.it("an escaped query uses its literal", function()
			t.eq(
				true,
				n.exec_lua(function(engine)
					local extract = require(engine .. ".extract")
					local bigram = require(engine .. ".bigram")
					return #extract.keys("require\\(") == #bigram.keys_of("require")
				end, ENGINE)
			)
		end)
	end)

	t.describe("bigram index", function()
		---Build the 4-file fixture index in the child and return the ids `query` keeps.
		---@param term string
		local function survivors(term)
			return n.exec_lua(function(q, engine)
				local bigram = require(engine .. ".bigram")
				local extract = require(engine .. ".extract")
				local idx = bigram.new(8)
				idx:add(0, "local error = handler")
				idx:add(1, "no match here at all")
				idx:add(2, "another error path")
				idx:add(3, "errno different word")
				local ids = idx:query(extract.keys(q))
				if ids == nil then
					return { full_scan = true }
				end
				table.sort(ids)
				return { ids = ids }
			end, term, ENGINE)
		end

		t.it("never drops a file that contains the literal", function()
			local ids = survivors("error").ids
			t.eq(true, vim.tbl_contains(ids, 0))
			t.eq(true, vim.tbl_contains(ids, 2))
		end)

		t.it("prunes a file with none of the bigrams", function()
			t.eq(false, vim.tbl_contains(survivors("error").ids, 1))
		end)

		t.it("falls back to a full scan when a bigram is absent from the index", function()
			t.eq({ full_scan = true }, survivors("zzqq"))
		end)

		t.it("reports file and column counts", function()
			t.eq(
				{ files = 4, has_columns = true },
				n.exec_lua(function(engine)
					local idx = require(engine .. ".bigram").new(8)
					for id, s in ipairs({ "aa bb", "bb cc", "cc dd", "dd ee" }) do
						idx:add(id - 1, s)
					end
					local stats = idx:stats()
					return { files = stats.files, has_columns = stats.columns > 0 }
				end, ENGINE)
			)
		end)
	end)

	t.describe("serialize", function()
		---Write an index for three files to a temp path in the child and return the path.
		local function write_fixture()
			return n.exec_lua(function(engine)
				local bigram = require(engine .. ".bigram")
				local files = { "/tmp/repo/alpha.lua", "/tmp/repo/beta.lua", "/tmp/repo/gamma.lua" }
				local bg = bigram.new(#files)
				bg:add(0, "local error = alpha handler")
				bg:add(1, "no relevant tokens here")
				bg:add(2, "another error in gamma")
				local path = vim.fn.tempname()
				assert(require(engine .. ".serialize").write({ root = "/tmp/repo", files = files, bigram = bg }, path))
				return path
			end, ENGINE)
		end

		t.it("round-trips files, columns and query results", function()
			local path = write_fixture()
			t.eq(
				{
					files = { "/tmp/repo/alpha.lua", "/tmp/repo/beta.lua", "/tmp/repo/gamma.lua" },
					kept = { 0, 2 },
					missing_is_nil = true,
				},
				n.exec_lua(function(p, engine)
					local loaded = require(engine .. ".serialize").read(p, "/tmp/repo")
					local keys = require(engine .. ".extract").keys("error")
					local kept = loaded.bigram:query(keys)
					table.sort(kept)
					return {
						files = loaded.files,
						kept = kept,
						missing_is_nil = loaded.bigram:query(require(engine .. ".bigram").keys_of("zzqq")) == nil,
					}
				end, path, ENGINE)
			)
		end)

		t.it("rejects a different root", function()
			local path = write_fixture()
			t.eq(
				nil,
				n.exec_lua(function(p, engine)
					return require(engine .. ".serialize").read(p, "/tmp/other")
				end, path, ENGINE)
			)
		end)

		for _, kind in ipairs({ "bad magic", "wrong version", "truncated file" }) do
			t.it("rejects " .. kind, function()
				local path = write_fixture()
				t.eq(
					nil,
					n.exec_lua(function(p, engine, k)
						local f = assert(io.open(p, "rb"))
						local raw = f:read("*a")
						f:close()
						local corrupt = {
							["bad magic"] = "X" .. raw:sub(2),
							["wrong version"] = raw:sub(1, 8) .. string.char(99, 0, 0, 0) .. raw:sub(13),
							["truncated file"] = raw:sub(1, 20),
						}
						local bad = vim.fn.tempname()
						local out = assert(io.open(bad, "wb"))
						out:write(corrupt[k])
						out:close()
						return require(engine .. ".serialize").read(bad, "/tmp/repo")
					end, path, ENGINE, kind)
				)
			end)
		end
	end)

	t.describe("index builder", function()
		-- Builds an index over a.lua/b.lua/c.lua in the child, exposed as `_G.fx`.
		t.before_each(function()
			n.exec_lua(function(engine)
				-- The builder reports completion through the global Toast.
				_G.Toast = function() end
				local index = require(engine .. ".index")
				local dir = vim.fn.tempname()
				vim.fn.mkdir(dir, "p")
				vim.fn.writefile({ "local error_handler = 1" }, dir .. "/a.lua")
				vim.fn.writefile({ "no relevant content" }, dir .. "/b.lua")
				vim.fn.writefile({ "another error case" }, dir .. "/c.lua")
				local built
				index.build(dir, { max_files = 100, max_file_size = 1024 * 1024 }, function(i)
					built = i
				end)
				vim.wait(3000, function()
					return built ~= nil
				end, 10)
				_G.fx = { index = index, built = built, dir = dir }
			end, ENGINE)
		end)

		t.after_each(function()
			n.exec_lua(function()
				_G.fx.built:stop()
				vim.fn.delete(_G.fx.dir, "rf")
			end)
		end)

		---Basenames of the files `query` keeps, sorted.
		---@param term string
		local function hits(term)
			return n.exec_lua(function(q)
				local out = vim.tbl_map(vim.fs.basename, _G.fx.built:query(q))
				table.sort(out)
				return out
			end, term)
		end

		t.it("builds a ready index and prunes non-matches", function()
			t.eq(true, n.exec_lua("return _G.fx.built.ready"))
			t.eq({ "a.lua", "c.lua" }, hits("error"))
		end)

		t.it("falls back to a full scan on a pure-regex query", function()
			t.eq(false, n.exec_lua('return _G.fx.built:query("(.)") ~= nil'))
		end)

		t.it("registers the ready index under its root and reports its files", function()
			t.eq(
				{ same = true, files = 3 },
				n.exec_lua(function()
					return { same = _G.fx.index.get(_G.fx.dir) == _G.fx.built, files = _G.fx.index.report().files }
				end)
			)
		end)

		t.it("makes a new file searchable after refresh", function()
			n.exec_lua(function()
				vim.fn.writefile({ "fresh error line" }, _G.fx.dir .. "/d.lua")
				_G.fx.built:refresh(_G.fx.dir .. "/d.lua")
			end)
			t.eq({ "a.lua", "c.lua", "d.lua" }, hits("error"))
		end)

		t.it("tombstones a deleted file", function()
			n.exec_lua(function()
				vim.fn.delete(_G.fx.dir .. "/a.lua")
				_G.fx.built:refresh(_G.fx.dir .. "/a.lua")
			end)
			t.eq({ "c.lua" }, hits("error"))
		end)

		t.it("keeps every file when new ones exceed the initial 32-slot pad", function()
			t.eq(
				60,
				n.exec_lua(function()
					for i = 1, 60 do
						local p = string.format("%s/z%02d.lua", _G.fx.dir, i)
						vim.fn.writefile({ "unique zebra token" }, p)
						_G.fx.built:refresh(p)
					end
					return #_G.fx.built:query("zebra")
				end)
			)
		end)
	end)
end)
