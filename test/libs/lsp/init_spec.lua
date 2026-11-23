local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Covers the Phase 1-3 behaviors of docs/dev-specs/lsp-infra-hardening.md (plus document_highlight):
--   1. enabled=false short-circuits vim.lsp.config / vim.lsp.enable
--   2. capabilities defaults to a snapshot table (passes vim.lsp validator)
--      AND a before_init hook re-resolves contributors at request time
--   3. late-added contributors reach before_init's resolution
--   4. unregister clears the dispatcher entry
--   5. inlay_hints / codelens / fold toggles are honored on LspAttach
--   6. capabilities.add warns when called after first_client_seen

t.describe("lsp infra hardening", function()
	t.before_each(function()
		h.clear()
		n.exec_lua(function()
			-- Globals the real config publishes beyond `h.clear()`.
			_G.Icon = require("beast.icon")
			_G.Key = Util.mod("beast.libs.key")
			require("beast.libs.lsp").setup({})
		end)
	end)

	t.describe("register / capabilities / unregister", function()
		t.it("enabled=false still records the dispatcher extras", function()
			t.eq(
				true,
				n.exec_lua(function()
					require("beast.libs.lsp").register("fake_disabled", {
						cmd = { "/nonexistent" },
						filetypes = { "x_fake" },
						enabled = function()
							return false
						end,
					})
					return require("beast.libs.lsp.attach").servers.fake_disabled ~= nil
				end)
			)
		end)

		t.it("enabled=false skips vim.lsp.config(cmd)", function()
			t.eq(
				true,
				n.exec_lua(function()
					require("beast.libs.lsp").register("fake_disabled", {
						cmd = { "/nonexistent" },
						filetypes = { "x_fake" },
						enabled = function()
							return false
						end,
					})
					return vim.lsp.config.fake_disabled == nil or vim.lsp.config.fake_disabled.cmd == nil
				end)
			)
		end)

		---Register `fake_caps` and report on what `vim.lsp.config` stored.
		---@return table
		local function register_caps()
			return n.exec_lua(function()
				require("beast.libs.lsp").register("fake_caps", { cmd = { "/bin/true" }, filetypes = { "x_thunk" } })
				local stored = vim.lsp.config.fake_caps
				-- vim.lsp.start_client validates capabilities is table-or-nil; the snapshot must pass that gate.
				local val_ok = pcall(vim.validate, "capabilities", stored.capabilities, "table", true)
				return {
					caps_type = type(stored.capabilities),
					before_init_type = type(stored.before_init),
					validates = val_ok,
				}
			end)
		end

		t.it("capabilities is a table (vim.lsp validator requires this)", function()
			t.eq("table", register_caps().caps_type)
		end)

		t.it("before_init is installed for late resolution", function()
			t.eq("function", register_caps().before_init_type)
		end)

		t.it("the capabilities snapshot passes the vim.lsp capabilities validator", function()
			t.eq(true, register_caps().validates)
		end)

		t.it("a late contributor reaches before_init's resolution and conf.capabilities", function()
			t.eq(
				{ "late_added", "late_added" },
				n.exec_lua(function()
					local Lsp = require("beast.libs.lsp")
					Lsp.register("fake_caps", { cmd = { "/bin/true" }, filetypes = { "x_thunk" } })
					local stored = vim.lsp.config.fake_caps
					Lsp.add_capabilities({ _testMarker = "late_added" })
					local params = { capabilities = stored.capabilities }
					stored.before_init(params, stored)
					---@diagnostic disable-next-line: undefined-field -- capabilities are open-ended; _testMarker is injected above
					return { params.capabilities._testMarker, stored.capabilities._testMarker }
				end)
			)
		end)

		t.it("a caller-supplied before_init is chained, not clobbered", function()
			t.eq(
				true,
				n.exec_lua(function()
					local user_called = false
					require("beast.libs.lsp").register("fake_chain", {
						cmd = { "/bin/true" },
						filetypes = { "x_chain" },
						before_init = function()
							user_called = true
						end,
					})
					vim.lsp.config.fake_chain.before_init({ capabilities = {} }, vim.lsp.config.fake_chain)
					return user_called
				end)
			)
		end)

		t.it("the enabled field is stripped from the native config", function()
			t.eq(
				true,
				n.exec_lua(function()
					require("beast.libs.lsp").register("fake_strip", {
						cmd = { "/bin/true" },
						filetypes = { "x_strip" },
						enabled = function()
							return true
						end,
					})
					return vim.lsp.config.fake_strip.enabled == nil
				end)
			)
		end)

		t.it("unregister clears the dispatcher entry", function()
			t.eq(
				{ true, true },
				n.exec_lua(function()
					local Lsp = require("beast.libs.lsp")
					local disp = require("beast.libs.lsp.attach")
					Lsp.register("fake_caps", { cmd = { "/bin/true" }, filetypes = { "x_thunk" } })
					local registered = disp.servers.fake_caps ~= nil
					Lsp.unregister("fake_caps")
					return { registered, disp.servers.fake_caps == nil }
				end)
			)
		end)
	end)

	t.describe("inlay hints / codelens config wiring", function()
		t.it("inlay_hints.enabled and codelens.enabled are honored", function()
			t.eq(
				{ true, true },
				n.exec_lua(function()
					local cfg = require("beast.libs.lsp.config")
					cfg.setup({ inlay_hints = { enabled = true }, codelens = { enabled = true } })
					return { cfg.inlay_hints.enabled, cfg.codelens.enabled }
				end)
			)
		end)

		-- Static check: the dispatcher source contains the apply_* call sites and uses
		-- vim.lsp.codelens.enable (replaced the manual autocmd + armed-flag guard).
		---@param pattern string Lua pattern searched for in attach.lua
		---@return boolean
		local function attach_has(pattern)
			return n.exec_lua(function(p)
				local src = table.concat(vim.fn.readfile("lua/beast/libs/lsp/attach.lua"), "\n")
				return src:find(p) ~= nil
			end, pattern)
		end

		t.it("dispatcher calls apply_inlay_hints", function()
			t.eq(true, attach_has("apply_inlay_hints%(client"))
		end)
		t.it("dispatcher calls apply_codelens", function()
			t.eq(true, attach_has("apply_codelens%(client"))
		end)
		t.it("codelens uses vim.lsp.codelens.enable", function()
			t.eq(true, attach_has("vim%.lsp%.codelens%.enable"))
		end)

		t.describe("document_highlight config wiring", function()
			t.it("document_highlight.enabled is honored", function()
				t.eq(
					true,
					n.exec_lua(function()
						local cfg = require("beast.libs.lsp.config")
						cfg.setup({ document_highlight = { enabled = true } })
						return cfg.document_highlight.enabled
					end)
				)
			end)
			t.it("dispatcher calls apply_document_highlight", function()
				t.eq(true, attach_has("apply_document_highlight%(client"))
			end)
			t.it("dispatcher gates on textDocument/documentHighlight", function()
				t.eq(true, attach_has("textDocument/documentHighlight"))
			end)
			t.it("dispatcher wires CursorHold/CursorHoldI", function()
				t.eq(true, attach_has('"CursorHold", "CursorHoldI"'))
			end)
			t.it("dispatcher wires CursorMoved to clear_references", function()
				t.eq(true, attach_has("clear_references"))
			end)
		end)
	end)

	t.describe("contributor ordering warning", function()
		-- Warnings go through vim.notify; record WARN-level calls in the child.
		---@return integer early, integer late
		local function warnings()
			local r = n.exec_lua(function()
				local caps = require("beast.libs.lsp.capabilities")
				local Lsp = require("beast.libs.lsp")
				caps.first_client_seen = false
				local warn_count = 0
				vim.notify = function(_, lvl)
					if lvl == vim.log.levels.WARN then
						warn_count = warn_count + 1
					end
				end
				Lsp.add_capabilities({ _early = true })
				local early = warn_count
				caps.first_client_seen = true
				Lsp.add_capabilities({ _late = true })
				return { early, warn_count }
			end)
			return r[1], r[2]
		end

		t.it("an early add does NOT warn", function()
			local early = warnings()
			t.eq(0, early)
		end)

		t.it("a late add warns once", function()
			local _, total = warnings()
			t.eq(1, total)
		end)

		t.it(":checkhealth runs cleanly", function()
			t.eq(
				true,
				n.exec_lua(function()
					return (pcall(require("beast.libs.lsp.health").check))
				end)
			)
		end)
	end)

	t.describe("lsp highlights", function()
		t.it("loads and defines the LspReference groups", function()
			t.eq(
				{ true, true, true },
				n.exec_lua(function()
					local groups = require("beast.libs.lsp.highlights").get()
					return {
						groups.LspReferenceText ~= nil,
						groups.LspReferenceRead ~= nil,
						groups.LspReferenceWrite ~= nil,
					}
				end)
			)
		end)
	end)
end)
