local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

local BRACKET = "[^\\]."
local QUOTE = '[^%w\\"][^%w]'

-- Pre-decoded termcodes (must match actions.lua byte-for-byte).
local function key(s)
	return vim.api.nvim_replace_termcodes(s, true, true, true)
end
local KEY_LEFT = key("<Left>")
local KEY_RIGHT = key("<Right>")
local KEY_BS = key("<BS>")
local KEY_BS_DEL = key("<BS><Del>")
local KEY_CR = key("<CR>")
local KEY_CR_INSIDE = key("<CR><C-o>O")

---Call `beast.libs.autopairs.actions[name](ctx)` in the child. `ctx.use_cfg` injects the default config.
---@param name string
---@param ctx table
---@param globals? { g?: boolean, b?: boolean } disable flags to set before the call
local function act(name, ctx, globals)
	return n.exec_lua(function(fn, c, flags)
		vim.b.beast_autopairs_disable = flags.b or nil
		vim.g.beast_autopairs_disable = flags.g or nil
		local cfg = require("beast.libs.autopairs.config")
		cfg.setup()
		if c.use_cfg then
			c.use_cfg = nil
			c.cfg = cfg.get()
		end
		return require("beast.libs.autopairs.actions")[fn](c)
	end, name, ctx, globals or {})
end

---@param fn string pairs-module function name
---@param ... any
local function pairs_call(fn, ...)
	return n.exec_lua(function(f, ...)
		return require("beast.libs.autopairs.pairs")[f](...)
	end, fn, ...)
end

t.describe("autopairs engine", function()
	t.before_each(h.clear)

	t.describe("pairs.neigh_matches", function()
		local function m(pat, before, after)
			return pairs_call("neigh_matches", pat, before, after)
		end

		t.it("bracket: mid-line plain", function()
			t.eq(true, m(BRACKET, "x", "y"))
		end)
		t.it("bracket: BOL (empty before)", function()
			t.eq(true, m(BRACKET, "", "y"))
		end)
		t.it("bracket: EOL (empty after)", function()
			t.eq(true, m(BRACKET, "x", ""))
		end)
		t.it("bracket: between brackets", function()
			t.eq(true, m(BRACKET, "(", ")"))
		end)
		t.it("bracket: after backslash -> no pair", function()
			t.eq(false, not not m(BRACKET, "\\", "x"))
		end)
		t.it("quote: between spaces", function()
			t.eq(true, m(QUOTE, " ", " "))
		end)
		t.it("quote: BOL+space", function()
			t.eq(true, m(QUOTE, "", " "))
		end)
		t.it("quote: before word -> no pair", function()
			t.eq(false, not not m(QUOTE, " ", "f"))
		end)
		t.it("quote: after word -> no pair", function()
			t.eq(false, not not m(QUOTE, "f", " "))
		end)
		t.it("quote: after escape -> no pair", function()
			t.eq(false, not not m(QUOTE, "\\", " "))
		end)
		t.it("quote: between alnums -> no pair", function()
			t.eq(false, not not m(QUOTE, "a", "b"))
		end)
	end)

	t.describe("pairs.is_symmetric", function()
		t.it("( is not symmetric", function()
			t.eq(false, not not pairs_call("is_symmetric", { close = ")" }, "("))
		end)
		t.it('" is symmetric', function()
			t.eq(true, pairs_call("is_symmetric", { close = '"' }, '"'))
		end)
		t.it("` is symmetric", function()
			t.eq(true, pairs_call("is_symmetric", { close = "`" }, "`"))
		end)
	end)

	t.describe("pairs.iter_active", function()
		t.it("yields the six default pairs in deterministic order", function()
			local seen = n.exec_lua(function()
				local cfg = require("beast.libs.autopairs.config")
				cfg.setup()
				local out = {}
				for k, _ in require("beast.libs.autopairs.pairs").iter_active(cfg.get()) do
					out[#out + 1] = k
				end
				return out
			end)
			t.eq(6, #seen)
			t.eq("\",',(,[,`,{", table.concat(seen, ","))
		end)
	end)

	t.describe("actions.open", function()
		t.it("( on empty line pairs", function()
			t.eq("()" .. KEY_LEFT, act("open", { open = "(", close = ")", neigh_pattern = BRACKET, before = "", after = "" }))
		end)
		t.it("( after backslash is literal", function()
			t.eq("(", act("open", { open = "(", close = ")", neigh_pattern = BRACKET, before = "\\", after = "" }))
		end)
		t.it("( before alnum still pairs (skip_next is separate)", function()
			t.eq("()" .. KEY_LEFT, act("open", { open = "(", close = ")", neigh_pattern = BRACKET, before = " ", after = "f" }))
		end)
		t.it('" before word does not pair (quote neighborhood)', function()
			t.eq('"', act("open", { open = '"', close = '"', neigh_pattern = QUOTE, before = " ", after = "f" }))
		end)
		t.it('" between spaces pairs', function()
			t.eq('""' .. KEY_LEFT, act("open", { open = '"', close = '"', neigh_pattern = QUOTE, before = " ", after = " " }))
		end)
	end)

	t.describe("actions.close", function()
		t.it("jumps over a matching closer", function()
			t.eq(KEY_RIGHT, act("close", { close = ")", after = ")" }))
		end)
		t.it("inserts when next is alnum", function()
			t.eq(")", act("close", { close = ")", after = "x" }))
		end)
		t.it("inserts at EOL", function()
			t.eq(")", act("close", { close = ")", after = "" }))
		end)
	end)

	t.describe("actions.closeopen", function()
		t.it('" jumps over', function()
			t.eq(KEY_RIGHT, act("closeopen", { open = '"', close = '"', neigh_pattern = QUOTE, before = "x", after = '"' }))
		end)
		t.it('" opens fresh', function()
			t.eq('""' .. KEY_LEFT, act("closeopen", { open = '"', close = '"', neigh_pattern = QUOTE, before = " ", after = " " }))
		end)
	end)

	t.describe("actions.bs", function()
		t.it("between ()", function()
			t.eq(KEY_BS_DEL, act("bs", { before = "(", after = ")", use_cfg = true }))
		end)
		t.it("between {}", function()
			t.eq(KEY_BS_DEL, act("bs", { before = "{", after = "}", use_cfg = true }))
		end)
		t.it('between ""', function()
			t.eq(KEY_BS_DEL, act("bs", { before = '"', after = '"', use_cfg = true }))
		end)
		t.it("between (} is literal", function()
			t.eq(KEY_BS, act("bs", { before = "(", after = "}", use_cfg = true }))
		end)
		t.it("at BOL is literal", function()
			t.eq(KEY_BS, act("bs", { before = "", after = "", use_cfg = true }))
		end)
		t.it("between () with global disable is literal", function()
			t.eq(KEY_BS, act("bs", { before = "(", after = ")", use_cfg = true }, { g = true }))
		end)
	end)

	t.describe("actions.cr", function()
		t.it("between {} splits", function()
			t.eq(KEY_CR_INSIDE, act("cr", { before = "{", after = "}", use_cfg = true }))
		end)
		t.it("between [] splits", function()
			t.eq(KEY_CR_INSIDE, act("cr", { before = "[", after = "]", use_cfg = true }))
		end)
		t.it("outside any pair is literal", function()
			t.eq(KEY_CR, act("cr", { before = "x", after = "y", use_cfg = true }))
		end)
	end)

	t.describe("disable flag", function()
		t.it("open with global disable is literal", function()
			t.eq("(", act("open", { open = "(", close = ")", neigh_pattern = BRACKET, before = "", after = "" }, { g = true }))
		end)
		t.it("close with global disable is literal", function()
			t.eq(")", act("close", { close = ")", after = ")" }, { g = true }))
		end)
		t.it("open with buffer disable is literal", function()
			t.eq("(", act("open", { open = "(", close = ")", neigh_pattern = BRACKET, before = "", after = "" }, { b = true }))
		end)
	end)

	t.describe("keymap install/uninstall", function()
		---Run `steps` (list of "enable"/"disable") and report state after each.
		local function roundtrip(steps)
			return n.exec_lua(function(list)
				local autopairs = require("beast.libs.autopairs")
				autopairs.setup()
				local out = {}
				for _, step in ipairs(list) do
					if step ~= "state" then
						autopairs[step]()
					end
					out[#out + 1] = {
						installed = autopairs.is_installed(),
						paren = vim.fn.maparg("(", "i") ~= "",
						close = vim.fn.maparg(")", "i") ~= "",
						quote = vim.fn.maparg('"', "i") ~= "",
						bs = vim.fn.maparg("<BS>", "i") ~= "",
						cr = vim.fn.maparg("<CR>", "i") ~= "",
					}
				end
				return out
			end, steps)
		end

		local ON = { installed = true, paren = true, close = true, quote = true, bs = true, cr = true }
		local OFF = { installed = false, paren = false, close = false, quote = false, bs = false, cr = false }

		t.it("starts uninstalled and maps nothing", function()
			t.eq({ OFF }, roundtrip({ "disable" }))
		end)

		t.it("enable installs the insert maps", function()
			t.eq({ OFF, ON }, roundtrip({ "disable", "enable" }))
		end)

		t.it("a second enable is a no-op", function()
			t.eq({ OFF, ON, ON }, roundtrip({ "disable", "enable", "enable" }))
		end)

		t.it("disable removes the maps", function()
			t.eq({ OFF, ON, OFF }, roundtrip({ "disable", "enable", "disable" }))
		end)

		t.it("is re-installable after disable", function()
			t.eq({ OFF, ON, OFF, ON }, roundtrip({ "disable", "enable", "disable", "enable" }))
		end)
	end)

	t.describe("toggle", function()
		t.it("sets then clears the global flag", function()
			t.eq(
				{ true, true },
				n.exec_lua(function()
					local autopairs = require("beast.libs.autopairs")
					vim.g.beast_autopairs_disable = nil
					autopairs.toggle()
					local set = vim.g.beast_autopairs_disable == true
					autopairs.toggle()
					return { set, not vim.g.beast_autopairs_disable }
				end)
			)
		end)
	end)
end)
