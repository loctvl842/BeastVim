-- =========================================================================
-- Test: beast.libs.lsp infra hardening
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-lsp.lua
-- Exit code: 0 = PASS, 1 = FAIL
--
-- Covers the Phase 1–3 behaviors of docs/dev-specs/lsp-infra-hardening.md:
--   1. enabled=false short-circuits vim.lsp.config / vim.lsp.enable
--   2. capabilities defaults to a snapshot table (passes vim.lsp validator)
--      AND a before_init hook re-resolves contributors at request time
--   3. late-added contributors reach before_init's resolution
--   4. unregister clears the dispatcher entry
--   5. inlay_hints / codelens / fold toggles are honored on LspAttach
--   6. capabilities.add warns when called after first_client_seen
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Stubs for globals that downstream submodules reference.
_G.Icon = setmetatable({}, {
	__index = function()
		return setmetatable({}, {
			__index = function()
				return ""
			end,
		})
	end,
})
_G.Util = { colors = {
	build = function()
		return {}
	end,
} }
_G.View = { win = { find_normal = function() end, wo = function() end } }
_G.Key = { safe_set = function() end, managed = {} }

-- =========================================================================
-- Test harness
-- =========================================================================

local passed = 0
local failed = 0

local function ok(name)
	passed = passed + 1
	print("  ✓ " .. name)
end

local function fail(name, msg)
	failed = failed + 1
	print("  ✗ " .. name .. ": " .. tostring(msg))
end

local function assert_true(name, cond, msg)
	if cond then
		ok(name)
	else
		fail(name, msg or "expected true")
	end
end

local function assert_eq(name, got, expected)
	if got == expected then
		ok(name)
	else
		fail(name, string.format("got %s, expected %s", tostring(got), tostring(expected)))
	end
end

-- =========================================================================
-- Setup
-- =========================================================================

local Lsp = require("beast.libs.lsp")
local caps = require("beast.libs.lsp.capabilities")
local cfg = require("beast.libs.lsp.config")
local disp = require("beast.libs.lsp.attach")

Lsp.setup({})

-- =========================================================================
-- Phase 1
-- =========================================================================

print("Phase 1: register / capabilities / unregister")

-- enabled=false short-circuit
Lsp.register("fake_disabled", {
	cmd = { "/nonexistent" },
	filetypes = { "x_fake" },
	enabled = function()
		return false
	end,
})
assert_true("enabled=false records dispatcher extras", disp.servers.fake_disabled ~= nil)
assert_true("enabled=false skips vim.lsp.config(cmd)", vim.lsp.config.fake_disabled == nil or vim.lsp.config.fake_disabled.cmd == nil)

-- capabilities: snapshot table + before_init re-resolves at request time
Lsp.register("fake_caps", { cmd = { "/bin/true" }, filetypes = { "x_thunk" } })
local stored = vim.lsp.config.fake_caps
assert_eq("capabilities is a table (vim.lsp validator requires this)", type(stored.capabilities), "table")
assert_eq("before_init installed for late resolution", type(stored.before_init), "function")

-- vim.lsp.start_client validates capabilities is table-or-nil; make sure
-- our snapshot would pass that gate so the runtime path doesn't blow up.
local val_ok, val_err = pcall(vim.validate, "capabilities", stored.capabilities, "table", true)
assert_true("snapshot passes vim.lsp capabilities validator", val_ok, val_err)

-- Late add must reach before_init's resolution
Lsp.add_capabilities({ _testMarker = "late_added" })
local params = { capabilities = stored.capabilities }
stored.before_init(params, stored)
assert_eq("late contributor reaches before_init", params.capabilities._testMarker, "late_added")
assert_eq("before_init updates conf.capabilities too", stored.capabilities._testMarker, "late_added")

-- Caller-supplied before_init must be chained, not clobbered
local user_called = false
Lsp.register("fake_chain", {
	cmd = { "/bin/true" },
	filetypes = { "x_chain" },
	before_init = function()
		user_called = true
	end,
})
vim.lsp.config.fake_chain.before_init({ capabilities = {} }, vim.lsp.config.fake_chain)
assert_true("user before_init is chained", user_called)

-- enabled field stripped from vim.lsp.config passthrough
Lsp.register("fake_strip", {
	cmd = { "/bin/true" },
	filetypes = { "x_strip" },
	enabled = function()
		return true
	end,
})
assert_true("enabled stripped from native cfg", vim.lsp.config.fake_strip.enabled == nil)

-- unregister
Lsp.unregister("fake_caps")
assert_true("unregister clears dispatcher entry", disp.servers.fake_caps == nil)

-- =========================================================================
-- Phase 2
-- =========================================================================

print("Phase 2: inlay hints / codelens config wiring")

-- Re-setup with toggles. Lsp.setup is idempotent (first call already ran),
-- so mutate config directly via its public setup().
cfg.setup({
	inlay_hints = { enabled = true },
	codelens = { enabled = true, events = { "BufEnter" } },
})
assert_eq("inlay_hints.enabled honored", cfg.inlay_hints.enabled, true)
assert_eq("codelens.enabled honored", cfg.codelens.enabled, true)
assert_eq("codelens.events override honored", cfg.codelens.events[1], "BufEnter")

-- Static check: dispatcher source contains the apply_* call sites.
local src = table.concat(vim.fn.readfile("lua/beast/libs/lsp/attach.lua"), "\n")
assert_true("dispatcher calls apply_inlay_hints", src:find("apply_inlay_hints%(client") ~= nil)
assert_true("dispatcher calls apply_codelens", src:find("apply_codelens%(client") ~= nil)
assert_true("codelens re-attach guard present", src:find("beast_lsp_codelens_armed") ~= nil)

-- =========================================================================
-- Phase 3
-- =========================================================================

print("Phase 3: contributor ordering warning")

-- Reset flag; record warnings via vim.notify monkey-patch.
caps.first_client_seen = false
local warn_count = 0
local orig_notify = vim.notify
vim.notify = function(_, lvl)
	if lvl == vim.log.levels.WARN then
		warn_count = warn_count + 1
	end
end

Lsp.add_capabilities({ _early = true })
assert_eq("early add does NOT warn", warn_count, 0)

caps.first_client_seen = true
Lsp.add_capabilities({ _late = true })
assert_eq("late add warns once", warn_count, 1)

vim.notify = orig_notify

-- Health check runs without crashing
local ok_health, err = pcall(require("beast.libs.lsp.health").check)
assert_true(":checkhealth runs cleanly", ok_health, err)

-- =========================================================================
-- Summary
-- =========================================================================

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
if failed > 0 then
	os.exit(1)
end
os.exit(0)
