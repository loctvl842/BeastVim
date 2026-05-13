local buffer_list = require("beast.libs.tabline.sections.buffer_list")
local buffers_mod = require("beast.libs.tabline.buffers")
local config = require("beast.libs.tabline.config")
local context = require("beast.libs.tabline.context")
local offset = require("beast.libs.tabline.sections.offset")
local tabpages = require("beast.libs.tabline.sections.tabpages")

local M = {}

---@class Beast.Tabline.State
---@field last_active_bufnr? integer
---@field augroup? integer
---@field last_diag_by_buf? table<integer, Beast.Tabline.DiagSummary>
---@field last_visible_buffers? integer[]
---@field last_left_hidden? integer
---@field last_right_hidden? integer
---@field dirty boolean
---@field cached_output? string
---@field cached_columns? integer

---@type Beast.Tabline.State
local state = {
	last_active_bufnr = nil,
	augroup = nil,
	last_diag_by_buf = nil,
	last_visible_buffers = {},
	last_left_hidden = 0,
	last_right_hidden = 0,
	dirty = true,
	cached_output = nil,
	cached_columns = nil,
}

--- Mark tabline as dirty so the next render() call rebuilds.
local function invalidate()
	state.dirty = true
end

--- Idempotent autocmd registration.
local function ensure_autocmds()
	-- stylua: ignore
	if state.augroup then return end

	state.augroup = vim.api.nvim_create_augroup("BeastTabline", { clear = true })

	-- Track last non-sidebar buffer as the logical active tab
	vim.api.nvim_create_autocmd("BufEnter", {
		group = state.augroup,
		callback = function(args)
			local bufnr = args.buf
			if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted and not buffers_mod.is_sidebar_buf(bufnr) then
				state.last_active_bufnr = bufnr
			end
			invalidate()
		end,
	})

	-- DiagnosticChanged: coalesce via vim.schedule
	vim.api.nvim_create_autocmd("DiagnosticChanged", {
		group = state.augroup,
		callback = function()
			invalidate()
			vim.schedule(function()
				vim.cmd("redrawtabline")
			end)
		end,
	})

	-- Layout-changing events
	vim.api.nvim_create_autocmd({
		"BufWinEnter",
		"BufWinLeave",
		"WinResized",
		"WinClosed",
		"BufAdd",
		"BufDelete",
		"BufModifiedSet",
		"VimResized",
		"TabEnter",
	}, {
		group = state.augroup,
		callback = function()
			invalidate()
			vim.schedule(function()
				vim.cmd("redrawtabline")
			end)
		end,
	})
end

--- Render the tabline. Called by Neovim via %!v:lua.require'beast.libs.tabline'.render()
---@return string
function M.render()
	-- Fast path: return cached output if nothing changed
	local columns = vim.o.columns
	if state.cached_output and not state.dirty and state.cached_columns == columns then
		return state.cached_output
	end

	local ctx = context.build(state)

	local parts = {}

	-- Offset section (sidebar title)
	parts[#parts + 1] = offset.render(ctx)

	-- Buffer list with truncation
	local buf_list_str, visible, left_hidden, right_hidden = buffer_list.render(ctx)
	parts[#parts + 1] = buf_list_str

	-- Stash truncation info for public API
	state.last_visible_buffers = visible
	state.last_left_hidden = left_hidden
	state.last_right_hidden = right_hidden

	-- Switch to fill highlight before the right-align gap
	parts[#parts + 1] = "%#BeastTlFill#"

	-- Right-align tabpages
	parts[#parts + 1] = "%="
	parts[#parts + 1] = tabpages.render(ctx)

	local output = table.concat(parts)

	-- Cache the result
	state.cached_output = output
	state.cached_columns = columns
	state.dirty = false

	return output
end

--- Setup the tabline library. Idempotent — safe to call multiple times.
---@param opts? Beast.Tabline.Config
function M.setup(opts)
	config.setup(opts)

	-- Register click handlers (overwriting is safe on re-setup)
	function _G.beast_tabline_buffer_click(bufnr, _, button, _)
		if button == "m" then
			vim.schedule(function()
				pcall(Buffer.delete, { buf = bufnr })
			end)
		elseif button == "l" then
			vim.api.nvim_set_current_buf(bufnr)
		end
	end

	function _G.beast_tabline_close_click(bufnr, _, button, _)
		if button == "l" then
			vim.schedule(function()
				pcall(Buffer.delete, { buf = bufnr })
			end)
		end
	end

	ensure_autocmds()

	-- Seed last_active_bufnr so sidebar-aware logic works on first open
	local cur = vim.api.nvim_get_current_buf()
	if vim.bo[cur].buflisted and not buffers_mod.is_sidebar_buf(cur) then
		state.last_active_bufnr = cur
	end

	vim.o.showtabline = 2
	vim.o.tabline = "%!v:lua.require'beast.libs.tabline'.render()"
end

-- =============================================================================
-- Public API helpers (for keymap integration)
-- =============================================================================

--- Switch to the n-th listed buffer.
---@param num integer 1-based index
function M.goto_buffer(num)
	local listed = buffers_mod.list()
	if num <= #listed then
		vim.api.nvim_set_current_buf(listed[num])
	end
end

--- Cycle to the next buffer.
function M.cycle_next()
	vim.cmd("bnext")
end

--- Cycle to the previous buffer.
function M.cycle_prev()
	vim.cmd("bprevious")
end

--- Move the current buffer one position to the right in the tabline.
function M.move_next()
	local current = vim.api.nvim_get_current_buf()
	local listed = buffers_mod.list()

	for i, bufnr in ipairs(listed) do
		if bufnr == current and i < #listed then
			local next_buf = listed[i + 1]
			listed[i] = next_buf
			listed[i + 1] = current
			for idx, buf in ipairs(listed) do
				vim.api.nvim_buf_set_var(buf, "buffer_order", idx)
			end
			invalidate()
			vim.cmd("redrawtabline")
			return
		end
	end
end

--- Move the current buffer one position to the left in the tabline.
function M.move_prev()
	local current = vim.api.nvim_get_current_buf()
	local listed = buffers_mod.list()

	for i, bufnr in ipairs(listed) do
		if bufnr == current and i > 1 then
			local prev_buf = listed[i - 1]
			listed[i] = prev_buf
			listed[i - 1] = current
			for idx, buf in ipairs(listed) do
				vim.api.nvim_buf_set_var(buf, "buffer_order", idx)
			end
			invalidate()
			vim.cmd("redrawtabline")
			return
		end
	end
end

--- Get the currently visible buffers in the tabline (after truncation).
---@return integer[]
function M.get_visible_buffers()
	return state.last_visible_buffers or {}
end

--- Get the truncation counts from the last render.
---@return integer left_hidden
---@return integer right_hidden
function M.get_truncation_counts()
	return state.last_left_hidden or 0, state.last_right_hidden or 0
end

--- Mark the tabline cache as dirty (for benchmarking and external invalidation).
function M._invalidate()
	invalidate()
end

return M
