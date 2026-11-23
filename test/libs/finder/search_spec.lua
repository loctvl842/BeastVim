local F = require("test.libs.finder.helpers.finder")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- beast.libs.finder.search: the headless file-search session. Needs fd, rg or find on PATH.

t.describe("finder search", function()
	local root

	t.before_each(function()
		F.setup()
		root = F.tmpdir({
			["lua/beast/init.lua"] = "x",
			["lua/beast/libs/explorer/init.lua"] = "x",
			["lua/beast/libs/finder/init.lua"] = "x",
			["lua/beast/util.lua"] = "x",
			["README.md"] = "x",
			[".hidden/secret.lua"] = "x",
		})
		n.exec_lua(function(root)
			_G.search = require("beast.libs.finder.search")
			_G.root = root
			---Run one query to completion and return the sorted relative paths, plus the result.
			_G.query = function(session, pattern)
				local out, res
				session:query(pattern, function(matched, result)
					out, res = matched, result
				end)
				vim.wait(3000, function()
					return out ~= nil and not res.loading
				end, 10)
				local texts = {}
				for _, item in ipairs(out or {}) do
					texts[#texts + 1] = item.text
				end
				table.sort(texts)
				return texts, res or {}
			end
			---Wait until a session has streamed all files.
			_G.loaded = function(session)
				vim.wait(3000, function()
					return not session.loading
				end, 10)
			end
			_G.s = _G.search.files({ cwd = root })
		end, root)
	end)

	t.after_each(function()
		n.exec_lua(function()
			_G.s:close()
		end)
		F.rmdir(root)
	end)

	---Query the shared session `_G.s` in the child.
	---@param pattern string
	---@return string[]
	local function query(pattern)
		return n.exec_lua(function(p)
			return (_G.query(_G.s, p))
		end, pattern)
	end

	t.it("is available when fd/rg/find is installed", function()
		t.eq(
			true,
			n.exec_lua(function()
				return _G.search.available()
			end)
		)
	end)

	t.it("matches files inside closed folders", function()
		t.eq({
			"lua/beast/init.lua",
			"lua/beast/libs/explorer/init.lua",
			"lua/beast/libs/finder/init.lua",
		}, query("in.lua"))
	end)

	t.describe("finder fuzzy syntax", function()
		t.it("excludes inverse terms", function()
			t.eq({ "lua/beast/init.lua", "lua/beast/libs/explorer/init.lua" }, query("init !finder"))
		end)

		t.it("ANDs terms", function()
			t.eq({ "lua/beast/libs/explorer/init.lua" }, query("explorer init"))
		end)
	end)

	t.it("excludes hidden files by default", function()
		t.eq({}, query("secret"))
	end)

	t.describe("limit", function()
		---@param limit integer
		---@param pattern string
		---@return string[] texts
		---@return boolean capped
		local function limited(limit, pattern)
			return unpack(n.exec_lua(function(limit, pattern)
				local session = _G.search.files({ cwd = _G.root, limit = limit })
				local texts, res = _G.query(session, pattern)
				session:close()
				return { texts, res.capped == true }
			end, limit, pattern))
		end

		t.it("caps results", function()
			local texts = limited(2, "lua")
			t.eq(2, #texts)
		end)

		t.it("flags capped", function()
			local _, capped = limited(2, "lua")
			t.eq(true, capped)
		end)

		t.it("returns exactly `limit` matches", function()
			local texts = limited(3, "in.lua")
			t.eq(3, #texts)
		end)

		t.it("does not flag exactly `limit` matches as capped", function()
			local _, capped = limited(3, "in.lua")
			t.eq(false, capped)
		end)
	end)

	t.it("delivers the last pattern's result after rapid successive queries", function()
		t.eq(
			1,
			n.exec_lua(function()
				_G.loaded(_G.s)
				local delivered = {}
				local function record(matched)
					delivered[#delivered + 1] = #matched
				end
				_G.s:query("in", record)
				_G.s:query("init", record)
				_G.s:query("explorer init", record)
				FH.settle(500)
				return delivered[#delivered]
			end)
		)
	end)

	t.it("calls back nothing when closed with a matcher in flight", function()
		t.eq(
			0,
			n.exec_lua(function()
				_G.loaded(_G.s)
				local late = 0
				_G.s:query("lua", function()
					late = late + 1
				end)
				_G.s:close()
				FH.settle(300)
				return late
			end)
		)
	end)

	t.it("re-runs a query issued mid-stream on completion", function()
		t.eq(
			{ "README.md" },
			n.exec_lua(function()
				local early = _G.search.files({ cwd = _G.root })
				local last
				early:query("README", function(matched, result)
					if not result.loading then
						last = vim.tbl_map(function(i)
							return i.text
						end, matched)
					end
				end)
				vim.wait(3000, function()
					return last ~= nil
				end, 10)
				early:close()
				return last
			end)
		)
	end)

	t.it("stops callbacks after close()", function()
		t.eq(
			0,
			n.exec_lua(function()
				local closed = _G.search.files({ cwd = _G.root })
				local calls = 0
				closed:query("lua", function()
					calls = calls + 1
				end)
				closed:close()
				FH.settle(300)
				return calls
			end)
		)
	end)

	t.describe("refresh()", function()
		t.it("answers the last query again on its own, with the new file", function()
			local r = n.exec_lua(function()
				local rerun = _G.search.files({ cwd = _G.root })
				_G.loaded(rerun)
				local seen
				rerun:query("fresh_file", function(matched, result)
					if not result.loading then
						seen = vim.tbl_map(function(i)
							return i.text
						end, matched)
					end
				end)
				vim.wait(1000, function()
					return seen ~= nil
				end, 10)
				local before = seen
				vim.fn.writefile({ "x" }, _G.root .. "/lua/beast/fresh_file.lua")
				seen = nil
				rerun:refresh()
				vim.wait(3000, function()
					return seen ~= nil
				end, 10)
				rerun:close()
				return { before = before, after = seen }
			end)
			t.eq({}, r.before)
			t.eq({ "lua/beast/fresh_file.lua" }, r.after)
		end)

		t.it("does nothing after close()", function()
			t.eq(
				true,
				n.exec_lua(function()
					local gone = _G.search.files({ cwd = _G.root })
					gone:close()
					return (pcall(function()
						gone:refresh()
						FH.settle(200)
					end))
				end)
			)
		end)

		t.it("picks up new files", function()
			n.exec_lua(function()
				vim.fn.writefile({ "x" }, _G.root .. "/lua/beast/fresh_file.lua")
				_G.s:refresh()
				_G.loaded(_G.s)
			end)
			t.eq({ "lua/beast/fresh_file.lua" }, query("fresh_file"))
		end)
	end)

	t.it("only reports real matches while streaming", function()
		t.eq(
			true,
			n.exec_lua(function()
				local streaming = _G.search.files({ cwd = _G.root })
				local partial
				streaming:query("README", function(matched, result)
					if result.loading then
						partial = partial or {}
						for _, item in ipairs(matched) do
							partial[#partial + 1] = item.text
						end
					end
				end)
				vim.wait(1000, function()
					return not streaming.loading
				end, 10)
				streaming:close()
				return partial == nil or #vim.tbl_filter(function(text)
					return text ~= "README.md"
				end, partial) == 0
			end)
		)
	end)
end)
