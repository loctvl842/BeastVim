local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Covers docs/dev-specs/key-cond.md: a keymap spec's `cond` (boolean or quick function) decides whether
-- the keymap is registered. A slow `cond(done)` leaves a placeholder until it answers.
-- Toast is replaced in the child by a recorder; everything else is the real lib.

t.describe("key cond", function()
	t.before_each(function()
		h.clear()
		n.exec_lua(function()
			local toasts = {}
			package.loaded["beast.libs.toast"] = setmetatable({}, {
				__call = function(_, msg, level, opts)
					toasts[#toasts + 1] = { msg = msg, level = level, opts = opts }
					return {}
				end,
			})
			local Key = require("beast.libs.key.core")
			local kc = { Key = Key, toasts = toasts, Cond = require("beast.libs.key.cond") }
			function kc.noop() end
			function kc.mapped(lhs, mode)
				return vim.fn.maparg(lhs, mode or "n", false, true).lhs ~= nil
			end
			function kc.registered(lhs, mode)
				local id = vim.api.nvim_replace_termcodes(lhs, true, true, true) .. " (" .. (mode or "n") .. ")"
				return Key.managed[id] ~= nil
			end
			---A slow cond whose `done` the test calls by hand.
			function kc.slow()
				local s = {}
				s.cond = function(done)
					s.done = done
				end
				return s
			end
			function kc.press(lhs, mode)
				vim.fn.maparg(lhs, mode or "n", false, true).callback()
			end
			---Let late answers land: they are dispatched through the event loop.
			function kc.drain()
				vim.wait(50, function()
					return false
				end, 5)
			end
			function kc.settle(until_fn)
				return vim.wait(500, until_fn, 5)
			end
			_G.kc = kc
		end)
	end)

	t.describe("boolean cond", function()
		---@param spec_cond boolean|nil  nil means the spec has no `cond` field
		---@return { mapped: boolean, registered: boolean }
		local function try(spec_cond)
			return n.exec_lua(function(c)
				local kc = _G.kc
				local opts = { desc = "x" }
				if c ~= "none" then
					opts.cond = c
				end
				kc.Key.safe_set("n", "<leader>ca", kc.noop, opts)
				return { mapped = kc.mapped("<leader>ca"), registered = kc.registered("<leader>ca") }
			end, spec_cond == nil and "none" or spec_cond)
		end

		t.it("cond = true registers", function()
			t.eq({ mapped = true, registered = true }, try(true))
		end)
		t.it("cond = false does not register", function()
			t.eq({ mapped = false, registered = false }, try(false))
		end)
		t.it("no cond registers", function()
			t.eq({ mapped = true, registered = true }, try(nil))
		end)
	end)

	t.describe("quick function cond", function()
		---@param result boolean
		local function try(result)
			return n.exec_lua(function(r)
				local kc = _G.kc
				kc.Key.safe_set("n", "<leader>cd", kc.noop, {
					desc = "fn",
					cond = function()
						return r
					end,
				})
				return { mapped = kc.mapped("<leader>cd"), registered = kc.registered("<leader>cd"), toasts = #kc.toasts }
			end, result)
		end

		t.it("function returning true registers", function()
			t.eq(true, try(true).mapped)
		end)
		t.it("function returning false does not register", function()
			local r = try(false)
			t.eq({ false, false }, { r.mapped, r.registered })
		end)
		t.it("a plain false is silent", function()
			t.eq(0, try(false).toasts)
		end)

		t.it("multi-mode registers every mode and runs cond once per call, not per mode", function()
			t.eq(
				{ true, true, 1 },
				n.exec_lua(function()
					local kc = _G.kc
					local calls = 0
					kc.Key.safe_set("nv", "<leader>cf", kc.noop, {
						desc = "multi-mode",
						cond = function()
							calls = calls + 1
							return true
						end,
					})
					return { kc.mapped("<leader>cf", "n"), kc.mapped("<leader>cf", "v"), calls }
				end)
			)
		end)
	end)

	t.describe("failing cond", function()
		---@return table
		local function run()
			return n.exec_lua(function()
				local kc = _G.kc
				kc.Key.safe_set("n", "<leader>cg", kc.noop, {
					desc = "raises",
					cond = function()
						error("boom")
					end,
				})
				return {
					mapped = kc.mapped("<leader>cg"),
					registered = kc.registered("<leader>cg"),
					count = #kc.toasts,
					level = kc.toasts[1] and kc.toasts[1].level,
					names_keymap = kc.toasts[1] ~= nil and kc.toasts[1].msg:find("raises", 1, true) ~= nil,
				}
			end)
		end

		t.it("a raising cond does not register", function()
			local r = run()
			t.eq({ false, false }, { r.mapped, r.registered })
		end)
		t.it("a raising cond toasts once", function()
			t.eq(1, run().count)
		end)
		t.it("the toast is a warning", function()
			t.eq("WARN", run().level)
		end)
		t.it("the toast names the keymap", function()
			t.eq(true, run().names_keymap)
		end)
	end)

	t.describe("cond is not a map option", function()
		t.it("cond does not reach vim.keymap.set", function()
			t.eq(
				{ cond_nil = true, desc = "cond true" },
				n.exec_lua(function()
					local kc = _G.kc
					kc.Key.safe_set("n", "<leader>ca", kc.noop, { desc = "cond true", cond = true })
					local km = vim.fn.maparg("<leader>ca", "n", false, true)
					return { cond_nil = km.cond == nil, desc = km.desc }
				end)
			)
		end)
		t.it("opts() drops cond", function()
			t.eq(
				true,
				n.exec_lua(function()
					local kc = _G.kc
					return kc.Key.opts({ "<leader>x", kc.noop, cond = true, desc = "d" }).cond == nil
				end)
			)
		end)
	end)

	t.describe("deleting", function()
		t.it("rhs = false deletes even when cond is false", function()
			t.eq(
				{ false, false },
				n.exec_lua(function()
					local kc = _G.kc
					kc.Key.safe_set("n", "<leader>ca", kc.noop, { desc = "cond true", cond = true })
					---@diagnostic disable-next-line: param-type-mismatch -- `false` deletes the keymap
					kc.Key.safe_set("n", "<leader>ca", false, { cond = false })
					return { kc.mapped("<leader>ca"), kc.registered("<leader>ca") }
				end)
			)
		end)
	end)

	t.describe("slow cond: placeholder", function()
		---Register a slow key, press the placeholder, then answer yes and press until the real action runs.
		---@return table
		local function run()
			return n.exec_lua(function()
				local kc = _G.kc
				local Key = kc.Key
				local ran = 0
				local s = kc.slow()
				Key.safe_set("n", "<leader>sa", function()
					ran = ran + 1
				end, { desc = "Pull requests", cond = s.cond })
				local r = { exists = kc.mapped("<leader>sa") and kc.registered("<leader>sa") }
				kc.press("<leader>sa")
				r.ran_on_placeholder = ran
				r.toast_count = #kc.toasts
				r.toast_msg = kc.toasts[1] and kc.toasts[1].msg
				local id = Key.id("<leader>sa", "n")
				r.conflicts_before = #Key.conflicts[id].calls

				s.done(true)
				r.swapped = kc.settle(function()
					kc.press("<leader>sa")
					return ran > 0
				end)
				r.conflicts_after = #Key.conflicts[id].calls
				r.warnings = #vim.tbl_filter(function(x)
					return x.level == "WARN"
				end, kc.toasts)
				return r
			end)
		end

		t.it("the key exists while the check runs", function()
			t.eq(true, run().exists)
		end)
		t.it("pressing the placeholder does not run the action", function()
			t.eq(0, run().ran_on_placeholder)
		end)
		t.it("pressing the placeholder toasts once, saying it is still checking", function()
			local r = run()
			t.eq(1, r.toast_count)
			t.eq("Pull requests: still checking", r.toast_msg)
		end)
		t.it("the placeholder is in the conflict history once", function()
			t.eq(1, run().conflicts_before)
		end)
		t.it("a yes swaps in the real action", function()
			t.eq(true, run().swapped)
		end)
		t.it("the swap adds no conflict record", function()
			t.eq(1, run().conflicts_after)
		end)
		t.it("a yes raises no warning", function()
			t.eq(0, run().warnings)
		end)
	end)

	t.describe("slow cond: no", function()
		t.it("a no removes the placeholder, silently", function()
			t.eq(
				{ true, 0 },
				n.exec_lua(function()
					local kc = _G.kc
					local s = kc.slow()
					kc.Key.safe_set("n", "<leader>sb", kc.noop, { desc = "slow no", cond = s.cond })
					s.done(false)
					local removed = kc.settle(function()
						return not kc.mapped("<leader>sb") and not kc.registered("<leader>sb")
					end)
					return { removed, #kc.toasts }
				end)
			)
		end)
	end)

	t.describe("slow cond: done answers from a process callback", function()
		t.it("the answer arrives from a fast callback", function()
			t.eq(
				true,
				n.exec_lua(function()
					local kc = _G.kc
					local ran = 0
					kc.Key.safe_set("n", "<leader>sc", function()
						ran = ran + 1
					end, {
						desc = "from a timer",
						cond = function(done)
							local timer = vim.uv.new_timer()
							timer:start(10, 0, function()
								timer:close()
								done(true)
							end)
						end,
					})
					return kc.settle(function()
						kc.press("<leader>sc")
						return ran > 0
					end)
				end)
			)
		end)
	end)

	t.describe("slow cond: only the first answer counts", function()
		t.it("a second done is ignored", function()
			t.eq(
				true,
				n.exec_lua(function()
					local kc = _G.kc
					local s = kc.slow()
					kc.Key.safe_set("n", "<leader>sd", kc.noop, { desc = "twice", cond = s.cond })
					s.done(true)
					s.done(false)
					kc.drain()
					return kc.mapped("<leader>sd")
				end)
			)
		end)
	end)

	t.describe("slow cond: done called before the function returns", function()
		t.it("an answer given at once registers the real keymap, no placeholder", function()
			t.eq(
				1,
				n.exec_lua(function()
					local kc = _G.kc
					local ran = 0
					kc.Key.safe_set("n", "<leader>se", function()
						ran = ran + 1
					end, {
						desc = "sync done",
						cond = function(done)
							done(true)
						end,
					})
					kc.press("<leader>se")
					return ran
				end)
			)
		end)
	end)

	t.describe("slow cond: timeout", function()
		---@return table
		local function run()
			return n.exec_lua(function()
				local kc = _G.kc
				kc.Cond.timeout_ms = 50
				local s = kc.slow()
				kc.Key.safe_set("n", "<leader>sf", kc.noop, { desc = "hangs", cond = s.cond })
				local removed = kc.settle(function()
					return not kc.mapped("<leader>sf")
				end)
				local r = {
					removed = removed,
					count = #kc.toasts,
					level = kc.toasts[1] and kc.toasts[1].level,
					says_why = kc.toasts[1] ~= nil and kc.toasts[1].msg:find("hangs disabled: check timed out", 1, true) ~= nil,
				}
				s.done(true)
				kc.drain()
				r.stays_removed = not kc.mapped("<leader>sf")
				return r
			end)
		end

		t.it("a check that never answers is removed", function()
			t.eq(true, run().removed)
		end)
		t.it("a timeout toasts once", function()
			t.eq(1, run().count)
		end)
		t.it("the timeout toast is a warning", function()
			t.eq("WARN", run().level)
		end)
		t.it("the timeout toast says why", function()
			t.eq(true, run().says_why)
		end)
		t.it("an answer after the timeout is thrown away", function()
			t.eq(true, run().stays_removed)
		end)
	end)

	t.describe("slow cond: superseded or deleted while pending", function()
		t.it("the newer registration is not overwritten by the late yes", function()
			t.eq(
				{ 0, 1 },
				n.exec_lua(function()
					local kc = _G.kc
					local first, second = 0, 0
					local s = kc.slow()
					kc.Key.safe_set("n", "<leader>sg", function()
						first = first + 1
					end, { desc = "old", cond = s.cond })
					kc.Key.safe_set("n", "<leader>sg", function()
						second = second + 1
					end, { desc = "new" })
					s.done(true)
					kc.drain()
					kc.press("<leader>sg")
					return { first, second }
				end)
			)
		end)

		t.it("a deleted key is not brought back by a late yes", function()
			t.eq(
				{ false, false },
				n.exec_lua(function()
					local kc = _G.kc
					local s = kc.slow()
					kc.Key.safe_set("n", "<leader>sh", kc.noop, { desc = "to delete", cond = s.cond })
					---@diagnostic disable-next-line: param-type-mismatch -- `false` deletes the keymap
					kc.Key.safe_set("n", "<leader>sh", false)
					s.done(true)
					kc.drain()
					return { kc.mapped("<leader>sh"), kc.registered("<leader>sh") }
				end)
			)
		end)

		t.it("a late no does not remove a newer registration", function()
			t.eq(
				true,
				n.exec_lua(function()
					local kc = _G.kc
					local s = kc.slow()
					kc.Key.safe_set("n", "<leader>si", kc.noop, { desc = "replaced then no", cond = s.cond })
					kc.Key.safe_set("n", "<leader>si", kc.noop, { desc = "newer" })
					s.done(false)
					kc.drain()
					return kc.mapped("<leader>si")
				end)
			)
		end)
	end)

	t.describe("slow cond: buffer-local", function()
		---@return table
		local function run()
			return n.exec_lua(function()
				local kc = _G.kc
				local buf = vim.api.nvim_create_buf(true, false)
				local other = vim.api.nvim_create_buf(true, false)
				local s, s_other = kc.slow(), kc.slow()
				kc.Key.safe_set("n", "<leader>sj", kc.noop, { desc = "local", buffer = buf, cond = s.cond })
				kc.Key.safe_set("n", "<leader>sj", kc.noop, { desc = "local", buffer = other, cond = s_other.cond })
				local r = { each_checked = type(s.done) == "function" and type(s_other.done) == "function" }
				vim.api.nvim_buf_delete(buf, { force = true })
				-- Late answers: the closed buffer's yes must not raise; the other buffer's no removes its placeholder.
				r.late_ok = pcall(function()
					s.done(true)
					s_other.done(false)
					kc.drain()
				end)
				r.closed_buffer_gone = not vim.api.nvim_buf_is_valid(buf)
				r.other_still_mapped = vim.api.nvim_buf_call(other, function()
					return kc.mapped("<leader>sj")
				end)
				return r
			end)
		end

		t.it("each buffer is checked on its own", function()
			t.eq(true, run().each_checked)
		end)
		t.it("the late answer of a closed buffer is thrown away without an error", function()
			local r = run()
			t.eq({ true, true }, { r.late_ok, r.closed_buffer_gone })
		end)
		t.it("a no for one buffer removes only that buffer's placeholder", function()
			t.eq(false, run().other_still_mapped)
		end)
	end)

	t.describe("slow cond: label-only entry and several modes", function()
		t.it("a label gets no placeholder while the check runs, and is listed once the check says yes", function()
			t.eq(
				{ false, true },
				n.exec_lua(function()
					local kc = _G.kc
					local s = kc.slow()
					kc.Key.safe_set("n", "<leader>sk", nil, { group = "Slow group", cond = s.cond })
					local before = kc.registered("<leader>sk")
					s.done(true)
					local listed = kc.settle(function()
						return kc.registered("<leader>sk")
					end)
					return { before, listed }
				end)
			)
		end)

		t.it("every mode gets a placeholder, and every mode is swapped on yes", function()
			t.eq(
				{ true, true, true },
				n.exec_lua(function()
					local kc = _G.kc
					local ran = 0
					local s = kc.slow()
					kc.Key.safe_set("nv", "<leader>sl", function()
						ran = ran + 1
					end, { desc = "multi", cond = s.cond })
					local placeholders = kc.mapped("<leader>sl", "n") and kc.mapped("<leader>sl", "v")
					s.done(true)
					kc.settle(function()
						kc.press("<leader>sl", "v")
						return ran > 0
					end)
					return { placeholders, ran > 0, kc.mapped("<leader>sl", "n") }
				end)
			)
		end)
	end)

	t.describe("packer lazy keys", function()
		-- forward cond to the temporary trigger
		---@param name string
		---@return table
		local function trigger(name)
			return n.exec_lua(function(which)
				local kc = _G.kc
				_G.Key = kc.Key
				local triggers = require("beast.libs.packer.triggers.keys")
				local loads = 0
				local function load_fn()
					loads = loads + 1
				end
				local plugin = { name = "demo" }
				if which == "off" then
					triggers.setup(plugin, { { "<leader>pa", kc.noop, desc = "gated off", cond = false } }, load_fn)
					return { mapped = kc.mapped("<leader>pa") }
				elseif which == "on" then
					triggers.setup(plugin, { { "<leader>pb", kc.noop, desc = "gated on", cond = true } }, load_fn)
					return { mapped = kc.mapped("<leader>pb") }
				elseif which == "bare" then
					triggers.setup(plugin, { "<leader>pc" }, load_fn)
					return { mapped = kc.mapped("<leader>pc") }
				end
				local checks = 0
				triggers.setup(plugin, {
					{
						"<leader>pd",
						kc.noop,
						desc = "counted",
						cond = function()
							checks = checks + 1
							return true
						end,
					},
				}, load_fn)
				kc.press("<leader>pd")
				local loaded = kc.settle(function()
					return loads == 1 and kc.mapped("<leader>pd")
				end)
				return { loaded = loaded, checks = checks }
			end, name)
		end

		t.it("cond = false leaves no lazy trigger", function()
			t.eq(false, trigger("off").mapped)
		end)
		t.it("cond = true keeps the lazy trigger", function()
			t.eq(true, trigger("on").mapped)
		end)
		t.it("a bare string key is unaffected", function()
			t.eq(true, trigger("bare").mapped)
		end)
		t.it("the trigger loads the plugin and installs the real key", function()
			t.eq(true, trigger("counted").loaded)
		end)
		t.it("the real key is not checked again", function()
			t.eq(1, trigger("counted").checks)
		end)
	end)
end)
