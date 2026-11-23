local F = require("test.libs.finder.helpers.finder")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Covers docs/dev-specs/finder-github-source.md Phase 2: a source with `retain_results` keeps its
-- previous list on screen until the first new item (or an empty finish) replaces it, `run_when_empty`
-- searches an empty prompt, `count` fills the prompt row only when a search finishes, and a plain
-- live source (live_grep-style) still clears the list at the start of every search.

---Run `fn` in the child.
local function child(fn, ...)
	return n.exec_lua(fn, ...)
end

---What the list was last told to show, comma-joined.
---@return string
local function shown()
	return child(function()
		return table.concat(_G.last_rendered, ",")
	end)
end

---The count label of the prompt ("" when hidden).
---@return string
local function count_text()
	return child(function()
		local buf = FH.panes().input.buf
		for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
			local vt = m[4].virt_text
			if vt and m[4].virt_text_pos == "right_align" and vt[1][2] == "BeastFinderListDir" then
				return vt[1][1]
			end
		end
		return ""
	end)
end

---Type into the prompt and let the debounce fire.
---@param text string
local function type_text(text)
	child(function(text)
		_G.pending = nil
		FH.type(text, 120)
	end, text)
end

---Whether the source was asked to search since the last `type_text`.
---@return boolean
local function searched()
	return child(function()
		return _G.pending ~= nil
	end)
end

---Feed the search in flight.
---@param ... string items to emit; the finish is `false`
local function emit(...)
	child(function(...)
		for _, text in ipairs({ ... }) do
			_G.pending({ idx = 1, score = 1, text = text })
		end
		FH.settle(150)
	end, ...)
end

local function finish()
	child(function()
		_G.pending(nil)
		FH.settle(150)
	end)
end

t.describe("finder stream retain_results", function()
	t.before_each(function()
		F.setup()
		child(function()
			-- Spy on list renders: what the list was last told to show.
			local ui = require("beast.libs.finder.ui")
			_G.last_rendered, _G.render_count = {}, 0
			local orig_render = ui.list.render
			ui.list.render = function(view, items, ...)
				_G.render_count = _G.render_count + 1
				_G.last_rendered = vim.tbl_map(function(it)
					return it.text
				end, items)
				return orig_render(view, items, ...)
			end
			-- Sources whose callbacks the test drives by hand.
			_G.make_source = function(extra)
				return vim.tbl_extend("force", {
					live = true,
					async = true,
					debounce_ms = 10,
					get = function(_, cb)
						_G.pending = cb
					end,
					cancel = function() end,
				}, extra)
			end
		end)
	end)

	t.after_each(F.close)

	t.describe("with retain_results + run_when_empty + count", function()
		t.before_each(function()
			child(function()
				FH.fake_source(
					"fake_retain",
					_G.make_source({
						initial_query = "q0",
						retain_results = true,
						run_when_empty = true,
						count = function(items)
							return ("%d/%d"):format(#items, #items)
						end,
					})
				)
				FH.open("fake_retain")
				FH.settle(50)
			end)
		end)

		t.it("searches immediately on open", function()
			t.eq(true, searched())
		end)

		t.it("hides the count while the first search runs", function()
			t.eq("", count_text())
		end)

		t.describe("once the first search finished", function()
			t.before_each(function()
				emit("a", "b")
				finish()
			end)

			t.it("renders the first results", function()
				t.eq("a,b", shown())
			end)

			t.it("shows the count", function()
				t.eq("2/2", count_text())
			end)

			t.describe("during a second search", function()
				local renders_before

				t.before_each(function()
					renders_before = child(function()
						_G.first_run = _G.pending
						_G.pending = nil
						return _G.render_count
					end)
					type_text("q1")
				end)

				t.it("starts it", function()
					t.eq(true, searched())
				end)

				t.it("keeps the old list on screen", function()
					t.eq("a,b", shown())
				end)

				t.it("renders nothing at search start", function()
					t.eq(
						renders_before,
						child(function()
							return _G.render_count
						end)
					)
				end)

				t.it("hides the count", function()
					t.eq("", count_text())
				end)

				t.describe("when the cancelled first run finishes late", function()
					t.before_each(function()
						child(function()
							_G.first_run({ idx = 1, score = 1, text = "stale" })
							_G.first_run(nil)
							FH.settle(150)
						end)
					end)

					t.it("does not replace the retained list", function()
						t.eq("a,b", shown())
					end)

					t.it("does not bring the count back", function()
						t.eq("", count_text())
					end)
				end)

				t.describe("when its first item arrives", function()
					t.before_each(function()
						emit("c")
					end)

					t.it("replaces the old list", function()
						t.eq("c", shown())
					end)

					t.it("shows the count once it finishes", function()
						finish()
						t.eq("1/1", count_text())
					end)

					t.describe("and a third search finds nothing", function()
						t.before_each(function()
							finish()
							type_text("q2")
						end)

						t.it("shows the previous results meanwhile", function()
							t.eq("c", shown())
						end)

						t.it("clears the list on an empty finish", function()
							finish()
							t.eq("", shown())
						end)

						t.it("reads 0/0 on an empty finish", function()
							finish()
							t.eq("0/0", count_text())
						end)
					end)
				end)
			end)

			t.it("searches on an empty prompt", function()
				type_text("")
				t.eq(true, searched())
			end)
		end)
	end)

	t.describe("a plain live source", function()
		t.before_each(function()
			child(function()
				_G.pending = nil
				FH.fake_source("fake_plain", _G.make_source({}))
				FH.open("fake_plain")
			end)
		end)

		t.it("does not search on open without initial_query", function()
			t.eq(false, searched())
		end)

		t.it("searches when typing", function()
			type_text("x")
			t.eq(true, searched())
		end)

		t.describe("after a search", function()
			t.before_each(function()
				type_text("x")
				emit("a")
				finish()
			end)

			t.it("renders the results", function()
				t.eq("a", shown())
			end)

			t.describe("then a new search", function()
				local renders_before

				t.before_each(function()
					renders_before = child(function()
						return _G.render_count
					end)
					type_text("xy")
				end)

				t.it("clears the list immediately", function()
					t.eq("", shown())
				end)

				t.it("renders the clear", function()
					t.eq(
						true,
						child(function(before)
							return _G.render_count > before
						end, renders_before)
					)
				end)

				t.it("shows no count label for sources without one", function()
					t.eq("", count_text())
				end)
			end)

			t.describe("then an empty prompt", function()
				t.before_each(function()
					type_text("")
				end)

				t.it("does not search", function()
					t.eq(false, searched())
				end)

				t.it("clears the list", function()
					t.eq("", shown())
				end)
			end)
		end)
	end)
end)
