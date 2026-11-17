--- Picker keys. Every key is written once: an action table says what a key does, a binding table
--- says which keys exist in which pane (input, list, preview). Adding a key is one line in `common`.
local action = require("beast.libs.finder.action")
local chain = require("beast.libs.finder.chain")
local match_hl = require("beast.libs.finder.match_hl")
local render = require("beast.libs.finder.render")
local ui = require("beast.libs.finder.ui")

local M = {}

---@param session Beast.Finder.Session
---@param delta integer positive = down, negative = up
local function move_cursor(session, delta)
	local old_offset = session.view.list._offset
	ui.list.move(session.view.list, delta)
	-- Re-apply match highlights when viewport scrolled to new rows
	if session.view.list._offset ~= old_offset and not session.level.query.source.live and session.view.list:is_valid() then
		local format_fn = render.formatters(session)
		local from, to = ui.list.visible_range(session.view.list)
		match_hl.apply_list(session.view.list.buf, session.level.query.matched, format_fn, from, to, session.view.list._separators and 2 or 1)
	end
	-- The hint names the highlighted row ("files changed in #12"), so it follows the cursor.
	render.hint(session)
	vim.cmd("redraw")
	render.schedule_preview(session)
end

--- Close the picker and hand the selected item to `opener` (once the picker is gone).
---@param session Beast.Finder.Session
---@param needs_file boolean only items with a file qualify (splits)
---@param opener fun(item: Beast.Finder.Item)
local function open_selected(session, needs_file, opener)
	local item = ui.list.selected(session.view.list)
	-- Informational rows (empty result, errors) are not actionable; neither are rows without a file for a split.
	if not item or item.message or (needs_file and not item.file) then
		return
	end
	session:close()
	vim.schedule(function()
		opener(item)
	end)
end

local function focus_input(session)
	vim.api.nvim_set_current_win(session.view.input.win)
	vim.cmd("startinsert!")
end

---@type table<string, fun(session: Beast.Finder.Session, key: string): string?>
local actions = {
	down = function(s)
		move_cursor(s, 1)
	end,
	up = function(s)
		move_cursor(s, -1)
	end,
	-- Mouse wheel: drive selection (the buffer only holds the visible slice, so
	-- native scrolling reveals nothing - move the cursor to re-render instead).
	wheel_down = function(s)
		move_cursor(s, 3)
	end,
	wheel_up = function(s)
		move_cursor(s, -3)
	end,
	-- Written out (not open_selected) because `confirmed` must be set before the picker closes.
	confirm = function(s)
		local item = ui.list.selected(s.view.list)
		if item and not item.message then
			s.confirmed = true
			s:close()
			vim.schedule(function()
				action.open(s, item)
			end)
		end
	end,
	split = function(s)
		open_selected(s, true, function(item)
			action.open_split(s.main_win, item)
		end)
	end,
	vsplit = function(s)
		open_selected(s, true, function(item)
			action.open_vsplit(s.main_win, item)
		end)
	end,
	copy = function(s)
		local item = ui.list.selected(s.view.list)
		if item then
			action.copy_path(item)
		end
	end,
	close = function(s)
		s:close()
	end,
	-- Chains: open the next picker / come back to the previous one.
	drill = function(s, key)
		chain.drill(s, key)
	end,
	back = function(s)
		chain.back(s)
	end,
	-- `<BS>` on an empty prompt goes back (when there is somewhere to go); otherwise it is a normal backspace.
	-- Runs as an `expr` mapping: the windows may not change inside it, so the pop is scheduled.
	backspace = function(s)
		if #s.stack > 0 and ui.input.get_text(s.view.input) == "" then
			vim.schedule(function()
				chain.back(s)
			end)
			return ""
		end
		return "<BS>"
	end,
	focus_input = focus_input,
	focus_preview = function(s)
		if s.view.preview and s.view.preview:is_valid() then
			vim.api.nvim_set_current_win(s.view.preview.win)
			-- The preview pane's keys are normal-mode keys; keep them reachable when
			-- the focus came from the prompt's insert mode.
			vim.cmd("stopinsert")
		end
	end,
	-- Nothing lies in that direction.
	noop = function() end,
}

---@alias Beast.Finder.KeyBinding { [1]: string, [2]: string, modes?: string[], expr?: boolean } lhs, action name, modes (default: the pane's), `expr` = the action returns the keys to feed

---@type Beast.Finder.KeyBinding[]
local move = {
	{ "<C-j>", "down" },
	{ "<C-k>", "up" },
}
---@type Beast.Finder.KeyBinding[]
local move_more = {
	{ "<C-n>", "down" },
	{ "<C-p>", "up" },
	{ "<Down>", "down" },
	{ "<Up>", "up" },
	{ "<Tab>", "down" },
	{ "<S-Tab>", "up" },
	{ "<ScrollWheelDown>", "wheel_down" },
	{ "<ScrollWheelUp>", "wheel_up" },
}
---@type Beast.Finder.KeyBinding[]
local pick = {
	{ "<CR>", "confirm" },
	{ "<C-s>", "split" },
	{ "<C-v>", "vsplit" },
}
---@type Beast.Finder.KeyBinding[]
local leave = {
	{ "<Esc>", "close", modes = { "n" } },
	{ "<C-c>", "close", modes = { "i", "n" } },
}

--- Insert/modify keys of the preview: they belong to the prompt, so they move there and type.
--- `/` is not redirected: Vim's own search runs in the preview buffer (`n`, `N`, `?`, `*`, `#` were never bound).
local preview_redirect = { "i", "I", "a", "A", "o", "O", "s", "S", "c", "C", "r", "R", "x", "X", "d", "D", "p", "P" }

---@class Beast.Finder.PaneKeys
---@field modes string[] modes the keys are bound in
---@field keys Beast.Finder.KeyBinding[][] binding groups
---@field chain "back"|"drill" which chain keys the pane has: `drill` (the keys of the enabled edges) and, for "back", also the keys that go back
---@field redirect? "printable"|string[] keys that move to the prompt and type themselves
---@field also_leader? boolean `<leader>` moves to the prompt instead of triggering a global mapping

---@type table<"input"|"list"|"preview", Beast.Finder.PaneKeys>
local panes = {
	input = {
		modes = { "i", "n" },
		chain = "back",
		keys = {
			move,
			move_more,
			leave,
			pick,
			{ { "<C-y>", "copy" }, { "<C-h>", "noop" }, { "<C-l>", "focus_preview" } },
		},
	},
	list = {
		modes = { "n" },
		chain = "drill",
		keys = {
			move,
			move_more,
			leave,
			pick,
			{ { "<C-h>", "focus_input" }, { "<C-l>", "focus_preview" } },
		},
		redirect = "printable",
	},
	preview = {
		modes = { "n" },
		chain = "drill",
		keys = {
			move,
			{ { "<Esc>", "close" } },
			{ { "<C-h>", "focus_input" }, { "<C-l>", "noop" } },
		},
		redirect = preview_redirect,
		also_leader = true,
	},
}

--- The keys of the picker that a chain key may not take (all but the chain keys themselves), normalized.
---@return table<string, true>
function M.reserved()
	local out = {}
	local groups = { move, move_more, pick, leave, { { "<C-y>" }, { "<C-h>" }, { "<C-l>" } } }
	for _, group in ipairs(groups) do
		for _, binding in ipairs(group) do
			out[chain.normalize_key(binding[1])] = true
		end
	end
	return out
end

--- The chain keys of a pane from the configuration: one `drill` binding per key some enabled edge follows,
--- and for the prompt the keys that go back (`<BS>` only on an empty prompt).
---@param kind "back"|"drill"
---@param session Beast.Finder.Session
---@return Beast.Finder.KeyBinding[]
local function chain_bindings(kind, session)
	local out, bound = {}, {}
	for _, key in ipairs(chain.keys(session)) do
		out[#out + 1] = { key, "drill" }
		bound[chain.normalize_key(key)] = true
	end
	-- A key that follows an edge of another picker does nothing here (not what Vim does with it: `<C-t>` would indent the prompt).
	for _, edge in ipairs(chain.enabled()) do
		if not bound[chain.normalize_key(edge.key)] then
			bound[chain.normalize_key(edge.key)] = true
			out[#out + 1] = { edge.key, "noop" }
		end
	end
	if kind == "back" then
		for _, key in ipairs(require("beast.libs.finder.config").chains.back) do
			if chain.same_key(key, "<BS>") then
				out[#out + 1] = { key, "backspace", modes = { "i" }, expr = true }
			else
				out[#out + 1] = { key, "back", modes = { "i" } }
			end
		end
	end
	return out
end

---@param session Beast.Finder.Session
---@param role "input"|"list"|"preview"
---@param spec Beast.Finder.PaneKeys
local function mount_pane(session, role, spec)
	local view = session.view[role]
	-- stylua: ignore
	if not view or not view:is_valid() then return end
	local opts = { buffer = view.buf, nowait = true }

	local groups = vim.list_extend({ chain_bindings(spec.chain, session) }, spec.keys)
	for _, group in ipairs(groups) do
		for _, binding in ipairs(group) do
			local run = actions[binding[2]]
			local lhs = binding[1]
			local map_opts = binding.expr and vim.tbl_extend("force", opts, { expr = true }) or opts
			vim.keymap.set(binding.modes or spec.modes, lhs, function()
				return run(session, lhs)
			end, map_opts)
		end
	end

	-- A key typed here belongs to the prompt: go there and type it (`type = false`: only go there).
	local function redirect(char, type)
		vim.keymap.set("n", char, function()
			focus_input(session)
			if type then
				vim.api.nvim_feedkeys(char, "n", false)
			end
		end, opts)
	end
	if spec.redirect == "printable" then
		for byte = string.byte(" "), string.byte("~") do
			redirect(string.char(byte), true)
		end
		-- Disable visual mode
		vim.keymap.set("n", "v", function() end, opts)
		vim.keymap.set("n", "V", function() end, opts)
	elseif spec.redirect then
		for _, char in
			ipairs(spec.redirect --[[@as string[] ]])
		do
			redirect(char, true)
		end
	end
	-- Block <leader> from triggering global mappings - redirect to input
	if spec.also_leader then
		vim.keymap.set("n", "<leader>", function()
			focus_input(session)
		end, opts)
	end
end

---@param session Beast.Finder.Session
function M.mount(session)
	for role, spec in pairs(panes) do
		mount_pane(session, role, spec)
	end
end

return M
