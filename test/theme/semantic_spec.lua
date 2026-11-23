local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Theme semantic colors (red/yellow/green derived from the palette).
t.describe("theme semantic colors", function()
	t.before_each(h.clear)

	---Run with_semantic over the defaults plus `overrides` and return { red, yellow, green }.
	---@param overrides? table<string, string>
	local function semantic(overrides)
		return n.exec_lua(function(o)
			local palette = require("beast.theme.palette")
			local p = palette.with_semantic(vim.tbl_extend("force", vim.deepcopy(palette.defaults), o or {}))
			return { p.red, p.yellow, p.green }
		end, overrides)
	end

	t.it("derives the defaults from the default palette", function()
		t.eq({ "#ffc0b9", "#fce094", "#b3f6c0" }, semantic())
	end)

	t.it("does not trust accent slots: shuffled order gives the same result", function()
		t.eq({ "#ffc0b9", "#fce094", "#b3f6c0" }, semantic({ accent1 = "#b3f6c0", accent2 = "#ffc0b9", accent3 = "#fce094" }))
	end)

	t.it("monokai-pro: orange accent2 wins neither red nor yellow", function()
		t.eq(
			{ "#ff6188", "#ffd866", "#a9dc76" },
			semantic({
				accent1 = "#ff6188",
				accent2 = "#fc9867",
				accent3 = "#ffd866",
				accent4 = "#a9dc76",
				accent5 = "#78dce8",
				accent6 = "#ab9df2",
			})
		)
	end)

	t.it("never picks a color twice, even when one is closest to two targets", function()
		local r, y, g = unpack(semantic({
			accent1 = "#ff6188",
			accent2 = "#a9dc76",
			accent3 = "#98d070",
			accent4 = "#88c060",
			accent5 = "#78b050",
			accent6 = "#68a040",
		}))
		t.eq("#ff6188", r)
		t.eq(true, y ~= r and y ~= g)
		t.eq(true, g ~= r)
	end)

	t.it("falls back to the default hexes for a grey-only palette", function()
		t.eq(
			{ "#ffc0b9", "#fce094", "#b3f6c0" },
			n.exec_lua(function()
				local palette = require("beast.theme.palette")
				local grey = {}
				for key in pairs(palette.defaults) do
					grey[key] = "#808080"
				end
				local p = palette.with_semantic(grey)
				return { p.red, p.yellow, p.green }
			end)
		)
	end)

	t.it("leaves base keys untouched", function()
		t.eq(
			true,
			n.exec_lua(function()
				local palette = require("beast.theme.palette")
				local p = palette.with_semantic(vim.deepcopy(palette.defaults))
				return p.accent2 == palette.defaults.accent2
			end)
		)
	end)

	t.it("exposes them through Theme.get() before refresh", function()
		t.eq("string", n.exec_lua('return type(require("beast.theme").get().red)'))
	end)

	t.it("exposes them through Theme.get() after refresh", function()
		t.eq(
			{ "string", "string", "string" },
			n.exec_lua(function()
				local theme = require("beast.theme")
				vim.cmd.colorscheme("default")
				theme.refresh()
				local p = theme.get()
				return { type(p.red), type(p.yellow), type(p.green) }
			end)
		)
	end)
end)
