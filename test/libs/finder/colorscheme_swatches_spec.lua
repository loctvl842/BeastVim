local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

t.describe("finder colorscheme swatches", function()
	t.before_each(function()
		h.clear()
		-- Isolate the on-disk cache from the user's real one.
		n.exec_lua(function()
			local tmp = vim.fn.tempname()
			vim.fn.mkdir(tmp, "p")
			local real_stdpath = vim.fn.stdpath
			vim.fn.stdpath = function(what)
				if what == "cache" then
					return tmp
				end
				return real_stdpath(what)
			end
			_G.tmp = tmp
			_G.theme_file = vim.fn.getcwd() .. "/colors/monokai-pro.lua"
			_G.swatches = require("beast.libs.finder.source.colorscheme_swatches")
		end)
	end)

	t.describe("worker", function()
		---Run the worker over two themes in the child and decode what it prints.
		local function run_worker()
			return n.exec_lua(function()
				local worker = vim.fn.getcwd() .. "/lua/beast/libs/finder/source/colorscheme_swatches_worker.lua"
				local res = vim
					.system({ vim.v.progpath, "--headless", "-u", "NONE", "-l", worker, vim.o.runtimepath, "monokai-pro", "no-such-theme" }, { text = true })
					:wait()
				local out = vim.json.decode(res.stdout)
				return {
					code = res.code,
					known_count = out["monokai-pro"] and #out["monokai-pro"],
					background = out["monokai-pro"][1],
					foreground = out["monokai-pro"][2],
					unknown_count = out["no-such-theme"] and #out["no-such-theme"],
					unknown_first_is_false = out["no-such-theme"][1] == false,
				}
			end)
		end

		t.it("prints ten colors per theme", function()
			local r = run_worker()
			t.eq(0, r.code)
			t.eq(10, r.known_count)
		end)

		t.it("takes the background from Normal.bg and the foreground from Normal.fg", function()
			local r = run_worker()
			t.eq({ "#2d2a2e", "#fcfcfa" }, { r.background, r.foreground })
		end)

		t.it("gives an unknown theme ten false entries", function()
			local r = run_worker()
			t.eq({ 10, true }, { r.unknown_count, r.unknown_first_is_false })
		end)
	end)

	t.describe("cache", function()
		---Run `ensure` for the real theme in the child and wait until it completes.
		---@return boolean done
		local function ensure()
			return n.exec_lua(function()
				local done = false
				_G.swatches.ensure({ { name = "monokai-pro", path = _G.theme_file } }, function()
					done = true
				end)
				return vim.wait(10000, function()
					return done
				end, 20)
			end)
		end

		t.it("misses on a cold cache", function()
			t.eq(
				true,
				n.exec_lua(function()
					return _G.swatches.get("monokai-pro", _G.theme_file) == nil
				end)
			)
		end)

		t.it("fills on ensure and then hits", function()
			t.eq(true, ensure())
			t.eq(
				10,
				n.exec_lua(function()
					return #_G.swatches.get("monokai-pro", _G.theme_file)
				end)
			)
		end)

		t.it("writes the cache file", function()
			ensure()
			t.eq(
				true,
				n.exec_lua(function()
					return vim.uv.fs_stat(_G.tmp .. "/beast-finder-colorscheme-swatches.json") ~= nil
				end)
			)
		end)

		t.it("does not spawn on a warm cache", function()
			ensure()
			t.eq(
				false,
				n.exec_lua(function()
					local fired = false
					_G.swatches.ensure({ { name = "monokai-pro", path = _G.theme_file } }, function()
						fired = true
					end)
					vim.wait(300, function()
						return fired
					end, 20)
					return fired
				end)
			)
		end)

		t.it("treats a theme file with a different mtime as stale", function()
			ensure()
			t.eq(
				true,
				n.exec_lua(function()
					local copy = _G.tmp .. "/monokai-pro.lua"
					vim.fn.writefile(vim.fn.readfile(_G.theme_file), copy)
					vim.uv.fs_utime(copy, 1000, 1000)
					return _G.swatches.get("monokai-pro", copy) == nil
				end)
			)
		end)
	end)

	t.describe("row format", function()
		---Format a colorschemes row in the child; `unset` is the 1-based index of a missing color.
		---@param item table
		---@param unset? integer
		local function row(item, unset)
			return n.exec_lua(function(it, missing)
				if it.swatches then
					for i = 1, 10 do
						it.swatches[i] = "#aabbcc"
					end
					if missing then
						it.swatches[missing] = false
					end
				end
				local r = require("beast.libs.finder.format").colorschemes(it, 46)
				local strip = r[2].chunks
				return {
					name = r[1].text,
					strip_len = #strip,
					first_hl = strip[1][2],
					fifth_hl = strip[5][2],
				}
			end, item, unset)
		end

		t.it("shows the name first, then ten squares plus ten gaps", function()
			local r = row({ text = "monokai-pro-classic", swatches = {} }, 3)
			t.eq({ "monokai-pro-classic", 20 }, { r.name, r.strip_len })
		end)

		t.it("uses the empty group for an unset role and its own group for a set one", function()
			local r = row({ text = "monokai-pro-classic", swatches = {} }, 3)
			t.eq("BeastFinderSwatchEmpty", r.fifth_hl)
			t.matches("^BeastFinderSwatch%x+$", r.first_hl)
		end)

		t.it("shortens a long name with ...", function()
			local name = n.exec_lua(function()
				local colors = {}
				for i = 1, 10 do
					colors[i] = "#aabbcc"
				end
				return require("beast.libs.finder.format").colorschemes({ text = "a-very-long-colorscheme-name-indeed", swatches = colors }, 46)[1].text
			end)
			t.eq(true, name:sub(-3) == "..." and #name < 35)
		end)

		t.it("shows ten dim squares for a pending theme", function()
			local r = row({ text = "x" })
			t.eq({ 20, "BeastFinderSwatchEmpty" }, { r.strip_len, r.first_hl })
		end)
	end)
end)
