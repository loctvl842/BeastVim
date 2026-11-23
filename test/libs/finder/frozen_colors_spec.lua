local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- highlights.lua reads the `Theme` / `Util` globals; give the child a fixed palette.
local COLORS = {
	dark2 = "#111111",
	dark1 = "#222222",
	background = "#333333",
	text = "#eeeeee",
	accent1 = "#ff0000",
	accent2 = "#ffaa00",
	accent3 = "#ffff00",
	accent4 = "#00ff00",
	accent5 = "#0000ff",
	accent6 = "#ff00ff",
	dimmed1 = "#aaaaaa",
	dimmed2 = "#999999",
	dimmed3 = "#888888",
	dimmed4 = "#777777",
	dimmed5 = "#666666",
}

t.describe("finder frozen highlight namespaces", function()
	t.before_each(function()
		h.clear()
		n.exec_lua(function(colors)
			_G.Theme = {
				get = function()
					return colors
				end,
			}
			_G.frozen = require("beast.libs.finder.highlights").freeze()
		end, COLORS)
	end)

	---Resolve a highlight attribute in a frozen namespace (`"list"` / `"input"`) of the child.
	---@param ns "list"|"input"
	---@param name string
	---@param attr string
	local function hl(ns, name, attr)
		return n.exec_lua(function(space, group, a)
			return vim.api.nvim_get_hl(_G.frozen[space], { name = group })[a]
		end, ns, name, attr)
	end

	t.describe("freeze", function()
		t.it("snapshots the list panel color", function()
			t.eq(tonumber("111111", 16), hl("list", "Normal", "bg"))
		end)

		t.it("snapshots the prompt panel color", function()
			t.eq(tonumber("222222", 16), hl("input", "Normal", "bg"))
		end)

		t.it("blends the input border into the prompt panel", function()
			t.eq(tonumber("222222", 16), hl("input", "FloatBorder", "bg"))
		end)

		t.it("gives end-of-buffer cells the panel color", function()
			t.eq(tonumber("111111", 16), hl("list", "EndOfBuffer", "bg"))
		end)

		t.it("copies the selected-row group", function()
			t.eq(tonumber("0000ff", 16), hl("list", "BeastFinderListSelected", "fg"))
		end)
	end)

	t.describe("swatch groups", function()
		t.it("are defined in the frozen list namespace", function()
			t.eq(
				tonumber("abcdef", 16),
				n.exec_lua(function()
					local group = require("beast.libs.finder.highlights").swatch("#abcdef")
					return vim.api.nvim_get_hl(_G.frozen.list, { name = group }).fg
				end)
			)
		end)

		t.it("are not global", function()
			t.eq(
				true,
				n.exec_lua(function()
					local group = require("beast.libs.finder.highlights").swatch("#abcdef")
					return next(vim.api.nvim_get_hl(0, { name = group })) == nil
				end)
			)
		end)
	end)

	t.it("keeps a window namespace through :colorscheme", function()
		t.eq(
			{
				attached = true,
				normal_bg = tonumber("111111", 16),
				swatch_fg = tonumber("abcdef", 16),
			},
			n.exec_lua(function()
				local highlights = require("beast.libs.finder.highlights")
				local group = highlights.swatch("#abcdef")
				local buf = vim.api.nvim_create_buf(false, true)
				local win = vim.api.nvim_open_win(buf, false, { relative = "editor", row = 0, col = 0, width = 10, height = 2, style = "minimal" })
				vim.api.nvim_win_set_hl_ns(win, _G.frozen.list)
				local attached = vim.api.nvim_get_hl_ns({ winid = win }) == _G.frozen.list
				vim.cmd.colorscheme("default")
				vim.o.background = "light"
				vim.cmd.colorscheme("default")
				local out = {
					attached = attached,
					normal_bg = vim.api.nvim_get_hl(_G.frozen.list, { name = "Normal" }).bg,
					swatch_fg = vim.api.nvim_get_hl(_G.frozen.list, { name = group }).fg,
				}
				vim.api.nvim_win_close(win, true)
				return out
			end)
		)
	end)

	t.it("routes swatches to the global namespace again after unfreeze", function()
		t.eq(
			tonumber("123456", 16),
			n.exec_lua(function()
				local highlights = require("beast.libs.finder.highlights")
				highlights.unfreeze()
				local group = highlights.swatch("#123456")
				return vim.api.nvim_get_hl(0, { name = group }).fg
			end)
		)
	end)
end)
