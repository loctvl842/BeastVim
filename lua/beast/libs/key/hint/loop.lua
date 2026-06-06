local config = require("beast.libs.key.config")
local index = require("beast.libs.key.hint.index")
local window = require("beast.libs.key.hint.window")

local M = {}

---@param state Beast.Key.Hint.State
---@return Beast.Key.Hint.Node?
local function walk_state(state)
	local full = {}
	for _, s in ipairs(state.trigger_segs) do
		table.insert(full, s)
	end
	for _, s in ipairs(state.sequence) do
		table.insert(full, s)
	end
	local node = index.walk(state.mode, full)
	if not node then
		return nil
	end
	-- Reject if unreachable in the current buffer.
	if not index.reachable(node, state.bufnr) then
		return nil
	end
	return node
end

---@param state Beast.Key.Hint.State
---@return boolean
function M.render(state)
	local node = walk_state(state)
	if not node then
		return false
	end
	local items = index.visible_children(node, state.bufnr)
	local crumbs = { state.trigger }
	for _, k in ipairs(state.sequence) do
		table.insert(crumbs, k)
	end
	local title = " " .. table.concat(crumbs, " ") .. " "
	window.open_or_update(state, title, items)
	vim.cmd("redraw")
	return true
end

---@param state Beast.Key.Hint.State
---@return string|nil sequence_to_feed -- canonical sequence (e.g. "<leader>ff") or nil to cancel
function M.run(state)
	local delay = config.hint.delay or 0

	-- Open immediately when delay == 0; otherwise schedule below.
	if delay <= 0 then
		M.render(state)
	end

	local opened = delay <= 0
	if not opened then
		state.delay_timer = assert((vim.uv or vim.loop).new_timer())
		state.delay_timer:start(
			delay,
			0,
			vim.schedule_wrap(function()
				if not opened and not state.done then
					opened = true
					M.render(state)
				end
			end)
		)
	end

	local function stop_timer()
		if state.delay_timer then
			state.delay_timer:stop()
			state.delay_timer:close()
			state.delay_timer = nil
		end
	end

	while true do
		local ok, raw = pcall(vim.fn.getcharstr)
		if not ok or raw == "" then
			stop_timer()
			return nil
		end

		local label = index.key_label(raw)

		-- Cancel: <Esc> or <C-c>
		if label == "<Esc>" or raw == "\003" then
			stop_timer()
			return nil
		end

		-- Backspace: pop one level (stay open at root).
		if label == "<BS>" then
			if #state.sequence > 0 then
				table.remove(state.sequence)
				if opened then
					M.render(state)
				end
			end
		else
			-- Autorepeat: user is holding the trigger key while the hint is
			-- open. Exit with a sentinel so the caller suspends the trigger
			-- keymap and feeds the press noremap (native cursor speed).
			if #state.trigger_segs == 1 and label == state.trigger_segs[1] and #state.sequence == 0 then
				stop_timer()
				return "\0autorepeat"
			end
			-- Descend
			table.insert(state.sequence, label)
			local node = walk_state(state)
			if not node then
				-- No match: feed the raw sequence verbatim.
				stop_timer()
				return state.trigger .. table.concat(state.sequence, "")
			end
			-- Leaf (no further children): feed verbatim and let Neovim resolve.
			-- This handles both executable leaves (Beast keymaps with rhs) and
			-- label-only leaves (e.g. vim builtins registered for discoverability)
			-- where the actual mapping lives in core/plugins/LSP.
			if not next(node.children) then
				stop_timer()
				return state.trigger .. table.concat(state.sequence, "")
			end
			-- Prefix node: keep waiting.
			if not opened then
				opened = true
			end
			M.render(state)
		end
	end
end

return M
