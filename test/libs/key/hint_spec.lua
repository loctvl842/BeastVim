local Screen = require("test.functional.ui.screen")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Automates the former manual checklist (tests/test-key-hint.lua): the press-and-wait key hint is
-- driven with real typed keys against an attached screen.

t.describe("key hint", function()
	local screen

	---Start a child with the sample maps under <leader>f and the hint enabled.
	---@param hint? table  `hint` config override
	local function start(hint)
		h.clear()
		screen = Screen.new(70, 16)
		n.exec_lua(function(hint_cfg)
			vim.g.mapleader = " "
			_G.fired = {}
			_G.Key = Util.mod("beast.libs.key")
			local function fire(name)
				return function()
					_G.fired[#_G.fired + 1] = name
				end
			end
			-- Group label (no rhs), then six sample maps under <leader>f
			Key.safe_set("n", "<leader>f", nil, { group = "file" })
			Key.safe_set("n", "<leader>ff", fire("find files"), { desc = "Find files" })
			Key.safe_set("n", "<leader>fg", fire("live grep"), { desc = "Live grep" })
			Key.safe_set("n", "<leader>fr", fire("recent files"), { desc = "Recent files" })
			Key.safe_set("n", "<leader>fb", fire("buffers"), { desc = "Buffers" })
			Key.safe_set("n", "<leader>fn", fire("new file"), { desc = "New file" })
			Key.safe_set("n", "<leader>fs", fire("save file"), { desc = "Save file" })
			Key.safe_set("n", "gf", fire("gf"), { desc = "Go to file" })
			hint_cfg.enabled = true
			Key.setup({ hint = hint_cfg })
		end, hint or {})
	end

	---Wait in the child until the hint loop is gone and late feeds have landed, then return what ran.
	---@return string[]
	local function fired()
		return n.exec_lua(function()
			vim.wait(200, function()
				return false
			end, 10)
			return _G.fired
		end)
	end

	t.describe("with the <leader> trigger", function()
		t.before_each(start)

		t.it("pressing <leader> opens the hint with the f group entry", function()
			n.feed("<space>")
			screen:expect({ any = " <leader> ", unchanged = true })
			screen:expect({ any = "%+file", unchanged = true })
		end)

		t.it("pressing <leader>f updates the hint to the group's entries", function()
			n.feed("<space>f")
			screen:expect({ any = " <leader> f ", unchanged = true })
			screen:expect({ any = "Find files", unchanged = true })
			screen:expect({ any = "Live grep", unchanged = true })
			screen:expect({ any = "Save file", unchanged = true })
			screen:expect({ none = "%+file", unchanged = true })
		end)

		t.it("pressing <leader>ff runs the action and closes the hint", function()
			n.feed("<space>f")
			screen:expect({ any = "Find files", unchanged = true })
			n.feed("f")
			screen:expect({ none = "Find files", unchanged = true })
			t.eq({ "find files" }, fired())
		end)

		t.it("pressing <leader> then <Esc> closes the hint with no side-effect", function()
			n.feed("<space>")
			screen:expect({ any = "%+file", unchanged = true })
			n.feed("<Esc>")
			screen:expect({ none = "%+file", unchanged = true })
			t.eq({}, fired())
		end)

		t.it("pressing <leader> then <BS> stays at the root level", function()
			n.feed("<space>")
			screen:expect({ any = "%+file", unchanged = true })
			n.feed("<BS>")
			screen:expect({ any = " <leader> ", unchanged = true })
			screen:expect({ any = "%+file", unchanged = true })
			screen:expect({ none = "Find files", unchanged = true })
		end)

		t.it("pressing <BS> inside <leader>f goes back one level", function()
			n.feed("<space>f")
			screen:expect({ any = "Find files", unchanged = true })
			n.feed("<BS>")
			screen:expect({ any = "%+file", unchanged = true })
			screen:expect({ none = "Find files", unchanged = true })
		end)

		t.it("pressing <leader>x closes the hint and runs nothing (x is not mapped)", function()
			n.feed("<space>")
			screen:expect({ any = "%+file", unchanged = true })
			n.feed("x")
			screen:expect({ none = "%+file", unchanged = true })
			t.eq({}, fired())
		end)
	end)

	t.describe("with triggers { 'g', 'f' } and a gf map", function()
		-- The `f` trigger must not open a second hint while the first hint UI is active/resolving.
		t.before_each(function()
			start({ triggers = { "g", "f" } })
		end)

		t.it("a fast g f resolves to gf once", function()
			n.feed("gf")
			t.eq({ "gf" }, fired())
		end)

		t.it("a slow g, then f, resolves to gf once", function()
			n.feed("g")
			screen:expect({ any = " g ", unchanged = true })
			n.feed("f")
			t.eq({ "gf" }, fired())
		end)
	end)
end)
