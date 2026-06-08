-- =========================================================================
-- Test: Autopairs engine (pairs, actions, keymap install/uninstall)
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-autopairs-engine.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

-- =========================================================================
-- Test helpers
-- =========================================================================

local passed = 0
local failed = 0

local function assert_test(name, cond, msg)
	if cond then
		passed = passed + 1
		io.write("  PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL: " .. name .. " — " .. (msg or "assertion failed") .. "\n")
	end
end

local function assert_eq(name, got, expected)
	if got == expected then
		passed = passed + 1
		io.write("  PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL: " .. name .. "\n         expected: " .. vim.inspect(expected) .. "\n         got:      " .. vim.inspect(got) .. "\n")
	end
end

-- =========================================================================
-- Pre-decoded termcodes (must match actions.lua to allow byte-for-byte compare)
-- =========================================================================

local KEY_LEFT = vim.api.nvim_replace_termcodes("<Left>", true, true, true)
local KEY_RIGHT = vim.api.nvim_replace_termcodes("<Right>", true, true, true)
local KEY_BS = vim.api.nvim_replace_termcodes("<BS>", true, true, true)
local KEY_BS_DEL = vim.api.nvim_replace_termcodes("<BS><Del>", true, true, true)
local KEY_CR = vim.api.nvim_replace_termcodes("<CR>", true, true, true)
local KEY_CR_INSIDE = vim.api.nvim_replace_termcodes("<CR><C-o>O", true, true, true)

-- =========================================================================
-- pairs.neigh_matches + pairs.is_symmetric + pairs.iter_active
-- =========================================================================

io.write("\n--- pairs.neigh_matches ---\n")
local pairs_mod = require("beast.libs.autopairs.pairs")

local BRACKET = "[^\\]."
local QUOTE = '[^%w\\"][^%w]'

assert_test("bracket: mid-line plain", pairs_mod.neigh_matches(BRACKET, "x", "y"))
assert_test("bracket: BOL (empty before)", pairs_mod.neigh_matches(BRACKET, "", "y"))
assert_test("bracket: EOL (empty after)", pairs_mod.neigh_matches(BRACKET, "x", ""))
assert_test("bracket: between brackets", pairs_mod.neigh_matches(BRACKET, "(", ")"))
assert_test("bracket: after backslash → no pair", not pairs_mod.neigh_matches(BRACKET, "\\", "x"), "backslash before should veto")

assert_test("quote: between spaces", pairs_mod.neigh_matches(QUOTE, " ", " "))
assert_test("quote: BOL+space", pairs_mod.neigh_matches(QUOTE, "", " "))
assert_test("quote: before word → no pair", not pairs_mod.neigh_matches(QUOTE, " ", "f"))
assert_test("quote: after word → no pair", not pairs_mod.neigh_matches(QUOTE, "f", " "))
assert_test("quote: after escape → no pair", not pairs_mod.neigh_matches(QUOTE, "\\", " "))
assert_test("quote: between alnums → no pair", not pairs_mod.neigh_matches(QUOTE, "a", "b"))

io.write("\n--- pairs.is_symmetric ---\n")
assert_test("is_symmetric: ( → false", not pairs_mod.is_symmetric({ close = ")" }, "("))
assert_test('is_symmetric: " → true', pairs_mod.is_symmetric({ close = '"' }, '"'))
assert_test("is_symmetric: ` → true", pairs_mod.is_symmetric({ close = "`" }, "`"))

io.write("\n--- pairs.iter_active ---\n")
do
	local cfg = require("beast.libs.autopairs.config")
	cfg.setup() -- reset to defaults
	local seen = {}
	for k, _ in pairs_mod.iter_active(cfg.get()) do
		seen[#seen + 1] = k
	end
	assert_eq("iter_active count", #seen, 6)
	-- Sorted deterministically
	assert_eq("iter_active order", table.concat(seen, ","), "\",',(,[,`,{")
end

-- =========================================================================
-- actions.open / close / closeopen
-- =========================================================================

io.write("\n--- actions.open ---\n")
local actions = require("beast.libs.autopairs.actions")

-- Make sure no stale disable flags from a previous run leak across tests.
vim.b.beast_autopairs_disable = nil
vim.g.beast_autopairs_disable = nil

assert_eq("open ( on empty line", actions.open({ open = "(", close = ")", neigh_pattern = BRACKET, before = "", after = "" }), "()" .. KEY_LEFT)
assert_eq("open ( after backslash → literal", actions.open({ open = "(", close = ")", neigh_pattern = BRACKET, before = "\\", after = "" }), "(")
assert_eq(
	"open ( before alnum → still pairs in P1 (skip_next is P2)",
	actions.open({ open = "(", close = ")", neigh_pattern = BRACKET, before = " ", after = "f" }),
	"()" .. KEY_LEFT
)
assert_eq(
	'open " before word → no pair (quote neighborhood)',
	actions.open({ open = '"', close = '"', neigh_pattern = QUOTE, before = " ", after = "f" }),
	'"'
)
assert_eq('open " between spaces', actions.open({ open = '"', close = '"', neigh_pattern = QUOTE, before = " ", after = " " }), '""' .. KEY_LEFT)

io.write("\n--- actions.close ---\n")
assert_eq("close ): jump over matching", actions.close({ close = ")", after = ")" }), KEY_RIGHT)
assert_eq("close ): insert when next is alnum", actions.close({ close = ")", after = "x" }), ")")
assert_eq("close ): insert at EOL", actions.close({ close = ")", after = "" }), ")")

io.write("\n--- actions.closeopen ---\n")
assert_eq('closeopen " jumps over', actions.closeopen({ open = '"', close = '"', neigh_pattern = QUOTE, before = "x", after = '"' }), KEY_RIGHT)
assert_eq(
	'closeopen " opens fresh',
	actions.closeopen({ open = '"', close = '"', neigh_pattern = QUOTE, before = " ", after = " " }),
	'""' .. KEY_LEFT
)

-- =========================================================================
-- actions.bs / actions.cr (need a config with the live pair table)
-- =========================================================================

io.write("\n--- actions.bs ---\n")
do
	local cfg = require("beast.libs.autopairs.config")
	cfg.setup()
	local C = cfg.get()

	assert_eq("bs between ()", actions.bs({ before = "(", after = ")", cfg = C }), KEY_BS_DEL)
	assert_eq("bs between {}", actions.bs({ before = "{", after = "}", cfg = C }), KEY_BS_DEL)
	assert_eq('bs between ""', actions.bs({ before = '"', after = '"', cfg = C }), KEY_BS_DEL)
	assert_eq("bs between (} → literal", actions.bs({ before = "(", after = "}", cfg = C }), KEY_BS)
	assert_eq("bs at BOL → literal", actions.bs({ before = "", after = "", cfg = C }), KEY_BS)

	-- Disable flag short-circuits to literal <BS>
	vim.g.beast_autopairs_disable = true
	assert_eq("bs between () with global disable → literal", actions.bs({ before = "(", after = ")", cfg = C }), KEY_BS)
	vim.g.beast_autopairs_disable = nil
end

io.write("\n--- actions.cr ---\n")
do
	local cfg = require("beast.libs.autopairs.config")
	cfg.setup()
	local C = cfg.get()

	assert_eq("cr between {}", actions.cr({ before = "{", after = "}", cfg = C }), KEY_CR_INSIDE)
	assert_eq("cr between [] → registered, splits", actions.cr({ before = "[", after = "]", cfg = C }), KEY_CR_INSIDE)
	assert_eq("cr outside any pair → literal", actions.cr({ before = "x", after = "y", cfg = C }), KEY_CR)
end

-- =========================================================================
-- Disable flag interactions on open/close
-- =========================================================================

io.write("\n--- disable flag ---\n")
do
	vim.g.beast_autopairs_disable = true
	assert_eq("open with global disable → literal", actions.open({ open = "(", close = ")", neigh_pattern = BRACKET, before = "", after = "" }), "(")
	assert_eq("close with global disable → literal", actions.close({ close = ")", after = ")" }), ")")
	vim.g.beast_autopairs_disable = nil

	vim.b.beast_autopairs_disable = true
	assert_eq("open with buffer disable → literal", actions.open({ open = "(", close = ")", neigh_pattern = BRACKET, before = "", after = "" }), "(")
	vim.b.beast_autopairs_disable = nil
end

-- =========================================================================
-- keymap.install / keymap.uninstall (idempotency + roundtrip)
-- =========================================================================

io.write("\n--- keymap install/uninstall ---\n")
do
	local autopairs = require("beast.libs.autopairs")
	autopairs.setup()

	-- Fresh start
	autopairs.disable()
	assert_test("starts uninstalled", not autopairs.is_installed())
	assert_test("( is unmapped before enable", vim.fn.maparg("(", "i") == "")

	autopairs.enable()
	assert_test("installed after enable", autopairs.is_installed())
	assert_test("( is mapped in insert", vim.fn.maparg("(", "i") ~= "")
	assert_test(") is mapped in insert", vim.fn.maparg(")", "i") ~= "")
	assert_test('" is mapped in insert', vim.fn.maparg('"', "i") ~= "")
	assert_test("<BS> is mapped in insert", vim.fn.maparg("<BS>", "i") ~= "")
	assert_test("<CR> is mapped in insert", vim.fn.maparg("<CR>", "i") ~= "")

	-- Second enable() must be a no-op (idempotency)
	autopairs.enable()
	assert_test("still installed after second enable", autopairs.is_installed())

	autopairs.disable()
	assert_test("not installed after disable", not autopairs.is_installed())
	assert_test("( is unmapped after disable", vim.fn.maparg("(", "i") == "")
	assert_test("<BS> is unmapped after disable", vim.fn.maparg("<BS>", "i") == "")

	-- Roundtrip again to prove uninstall left clean state
	autopairs.enable()
	assert_test("re-installable after disable", autopairs.is_installed() and vim.fn.maparg("(", "i") ~= "")
	autopairs.disable()
end

io.write("\n--- toggle flag ---\n")
do
	local autopairs = require("beast.libs.autopairs")
	vim.g.beast_autopairs_disable = nil
	autopairs.toggle()
	assert_test("toggle sets global flag", vim.g.beast_autopairs_disable == true)
	autopairs.toggle()
	assert_test("toggle clears global flag", not vim.g.beast_autopairs_disable)
end

-- =========================================================================
-- Summary
-- =========================================================================

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
if failed > 0 then
	os.exit(1)
end
os.exit(0)
