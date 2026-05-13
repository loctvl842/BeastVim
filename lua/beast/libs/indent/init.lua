local config = require("beast.libs.indent.config")

local M = {}

M.enabled = false

local ns = vim.api.nvim_create_namespace("beast_indent")
local has_repeat_lb = vim.fn.has("nvim-0.10") == 1

---@class Beast.Indent.State
---@field buf number
---@field changedtick number
---@field shiftwidth number
---@field leftcol number
---@field breakindent boolean
---@field indents table<number, number>
---@field blanks table<number, boolean>

---@type table<number, Beast.Indent.State>
local states = {}

---@type table<string, vim.api.keyset.set_extmark[]>
local cache_extmarks = {}

local augroup

-- =============================================================================
-- INDENT CALCULATION
-- =============================================================================

---@param win number
---@param buf number
---@return Beast.Indent.State
local function get_state(win, buf)
	local prev = states[win]
	local changedtick = vim.b[buf].changedtick

	if prev and prev.buf == buf and prev.changedtick == changedtick then
		return prev
	end

	local sw = vim.bo[buf].shiftwidth
	if sw == 0 then
		sw = vim.bo[buf].tabstop
	end

	---@type Beast.Indent.State
	local state = {
		buf = buf,
		changedtick = changedtick,
		shiftwidth = sw,
		leftcol = vim.api.nvim_win_call(win, vim.fn.winsaveview).leftcol,
		breakindent = vim.wo[win].breakindent and vim.wo[win].wrap,
		indents = {},
		blanks = {},
	}
	states[win] = state
	return state
end

---@param line number 1-indexed
---@param state Beast.Indent.State
---@return number
local function get_indent(line, state)
	local cached = state.indents[line]
	if cached then
		return cached
	end

	local next_nb = vim.fn.nextnonblank(line)
	local indent

	if next_nb ~= line then
		-- Blank line: interpolate from surrounding non-blank lines
		state.blanks[line] = true
		local prev_nb = vim.fn.prevnonblank(line)
		local prev_indent = prev_nb > 0 and vim.fn.indent(prev_nb) or 0
		local next_indent = next_nb > 0 and vim.fn.indent(next_nb) or 0
		indent = math.min(prev_indent, next_indent)
		-- When surrounding indents differ, the blank line belongs to the deeper block
		if prev_indent ~= next_indent and indent > 0 then
			indent = indent + state.shiftwidth
		end
	else
		indent = vim.fn.indent(line)
	end

	state.indents[line] = indent
	return indent
end

-- =============================================================================
-- EXTMARK GENERATION
-- =============================================================================

---@param level number
---@param hl string|string[]
---@return string
local function get_hl(level, hl)
	if type(hl) == "string" then
		return hl
	end
	return hl[(level - 1) % #hl + 1]
end

---@param indent number
---@param state Beast.Indent.State
---@return vim.api.keyset.set_extmark[]
local function get_extmarks(indent, state)
	local key = indent .. ":" .. state.leftcol .. ":" .. state.shiftwidth
	if cache_extmarks[key] then
		return cache_extmarks[key]
	end

	local sw = state.shiftwidth
	local levels = math.floor(indent / sw)
	local marks = {}

	for i = 1, levels do
		local col = (i - 1) * sw - state.leftcol
		if col >= 0 then
			marks[#marks + 1] = {
				virt_text = { { config.char, get_hl(i, config.hl) } },
				virt_text_pos = "overlay",
				virt_text_win_col = col,
				hl_mode = "combine",
				priority = config.priority,
				ephemeral = true,
				virt_text_repeat_linebreak = has_repeat_lb and state.breakindent or nil,
			}
		end
	end

	cache_extmarks[key] = marks
	return marks
end

-- =============================================================================
-- DECORATION PROVIDER
-- =============================================================================

---@param win number
---@param buf number
---@param top number 0-indexed from provider
---@param bottom number 0-indexed from provider
local function on_win(_, win, buf, top, bottom)
	-- stylua: ignore
	if not M.enabled then return end
	-- stylua: ignore
	if not config.filter(buf, win) then return end

	local state = get_state(win, buf)

	vim.api.nvim_buf_call(buf, function()
		for line = top + 1, bottom + 1 do
			local indent = get_indent(line, state)
			if indent > 0 then
				local marks = get_extmarks(indent, state)
				for _, opts in ipairs(marks) do
					vim.api.nvim_buf_set_extmark(buf, ns, line - 1, 0, opts)
				end
			end
		end
	end)
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

function M.setup(opts)
	config.setup(opts)
end

function M.enable()
	-- stylua: ignore
	if M.enabled then return end
	M.enabled = true

	vim.api.nvim_set_decoration_provider(ns, {
		on_win = on_win,
	})

	augroup = vim.api.nvim_create_augroup("BeastIndent", { clear = true })

	vim.api.nvim_create_autocmd({ "WinClosed", "BufDelete", "BufWipeout" }, {
		group = augroup,
		callback = function()
			for win in pairs(states) do
				if not vim.api.nvim_win_is_valid(win) then
					states[win] = nil
				end
			end
		end,
	})

	vim.api.nvim_create_autocmd("ColorScheme", {
		group = augroup,
		callback = function()
			cache_extmarks = {}
		end,
	})
end

function M.disable()
	-- stylua: ignore
	if not M.enabled then return end
	M.enabled = false

	vim.api.nvim_set_decoration_provider(ns, {})

	if augroup then
		vim.api.nvim_del_augroup_by_id(augroup)
		augroup = nil
	end

	states = {}
	cache_extmarks = {}
	vim.cmd("redraw!")
end

return M
