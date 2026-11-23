local Screen = require("test.functional.ui.screen")
local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

t.describe("messages router", function()
	t.before_each(h.clear)

	---Resolve (kind, text) against the configured routes in the child.
	---@param kind string
	---@param text string
	local function resolve(kind, text)
		return n.exec_lua(function(k, s)
			local routes = require("beast.libs.messages.config").routes
			local r = require("beast.libs.messages.router").resolve(routes, k, s)
			return { found = r ~= nil, r = r }
		end, kind, text)
	end

	t.describe("flatten", function()
		t.it("joins chunks and trims", function()
			t.eq(
				"E492: Not an editor command: foo",
				n.exec_lua(function()
					return require("beast.libs.messages.router").flatten({
						{ 0, " E492: " },
						{ 0, "Not an editor command: foo " },
					})
				end)
			)
		end)
	end)

	t.describe("resolve", function()
		t.it("turns E486 into a search warning toast", function()
			local r = resolve("emsg", "E486: Pattern not found: zzz").r
			t.eq("Pattern not found: zzz", r.text)
			t.eq(vim.log.levels.WARN, r.level)
			t.eq("Search", r.title)
		end)

		t.it("rewrites forward search wrap", function()
			t.eq("Hit BOTTOM, continuing at TOP", resolve("wmsg", "search hit BOTTOM, continuing at TOP").r.text)
		end)

		t.it("rewrites backward search wrap", function()
			t.eq("Hit TOP, continuing at BOTTOM", resolve("wmsg", "search hit TOP, continuing at BOTTOM").r.text)
		end)

		t.it("drops search_count", function()
			t.eq(true, resolve("search_count", " [2/3]").r.drop)
		end)

		t.it("makes other errors error toasts", function()
			t.eq(vim.log.levels.ERROR, resolve("emsg", "E492: Not an editor command: foo").r.level)
		end)

		t.it("makes other warnings warn toasts", function()
			t.eq(vim.log.levels.WARN, resolve("wmsg", "W10: Changing a readonly file").r.level)
		end)

		t.it("keeps the first line of multi-line errors plus spill", function()
			t.eq("E5108: Error executing lua [+2]", resolve("emsg", "E5108: Error executing lua\nstack line 1\nstack line 2").r.text)
		end)

		t.it("leaves echo to ui2", function()
			t.eq(false, resolve("echo", "hello").found)
		end)

		t.it("leaves list output to ui2", function()
			t.eq(false, resolve("list_cmd", "  1 %a file").found)
		end)
	end)

	t.describe("ui2 integration", function()
		local screen

		t.before_each(function()
			screen = Screen.new(100, 30)
			n.exec_lua(function()
				vim.o.cmdheight = 0
				_G.toasts = {}
				_G.Toast = function(msg, level, opts)
					_G.toasts[#_G.toasts + 1] = { msg = msg, level = level, title = opts and opts.title }
				end
				require("beast.libs.messages").setup()
			end)
		end)

		---@return table[]
		local function toasts()
			return n.exec_lua("return _G.toasts")
		end

		---Wait in the child until `count` toasts arrived.
		local function wait_toasts(count)
			n.exec_lua(function(c)
				vim.wait(2000, function()
					return #_G.toasts >= c
				end, 10)
			end, count)
		end

		t.it("installs the router", function()
			t.eq(true, n.exec_lua("return require('beast.libs.messages').is_routing()"))
		end)

		t.it("turns a failed search into a toast without a hit-enter prompt", function()
			n.api.nvim_buf_set_lines(0, 0, -1, false, { "abc", "abd" })
			n.feed("/zzz<CR>")
			wait_toasts(1)
			t.eq("Pattern not found: zzz", toasts()[1].msg)
			t.eq(false, n.api.nvim_get_mode().blocking)
		end)

		t.it("shows one toast for a failed search that wraps first", function()
			n.api.nvim_buf_set_lines(0, 0, -1, false, { "abc", "abd" })
			n.api.nvim_win_set_cursor(0, { 2, 0 })
			n.feed("/qqq<CR>")
			wait_toasts(1)
			-- let any (wrongly) pending second toast arrive
			n.exec_lua("vim.wait(200)")
			local list = toasts()
			t.eq(1, #list)
			t.eq("Search", list[1].title)
		end)

		t.it("turns an unknown command into a non-blocking error toast", function()
			n.feed(":nosuchcmd<CR>")
			wait_toasts(1)
			local list = toasts()
			t.eq(vim.log.levels.ERROR, list[#list].level)
			t.eq(false, n.api.nvim_get_mode().blocking)
		end)

		t.it("styles the message window like a toast", function()
			n.feed(":echo 'hello'<CR>")
			t.eq(
				true,
				n.exec_lua(function()
					local found
					vim.wait(2000, function()
						for _, w in ipairs(vim.api.nvim_list_wins()) do
							if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "msg" then
								found = vim.wo[w].winhighlight
								return true
							end
						end
						return false
					end, 10)
					return found ~= nil and found:find("Normal:BeastMessagesMsg", 1, true) ~= nil
				end)
			)
		end)
	end)
end)
