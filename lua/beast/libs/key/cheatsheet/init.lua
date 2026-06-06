local Action = require("beast.libs.key.cheatsheet.action")
local Main = require("beast.libs.key.cheatsheet.main")
local api = require("beast.libs.key.api")
local config = require("beast.libs.key.config")
local state = require("beast.libs.key.cheatsheet.state")

local M = {}

-- =============================================================================
-- Actions
-- =============================================================================

local _actions_handler = {}

local actions = setmetatable({}, {
	__index = function(_, key)
		if _actions_handler[key] ~= nil then
			return _actions_handler[key]
		end
		error("Invalid action: " .. key)
	end,
})

function _actions_handler.close()
  --stylua: ignore
  if state.closed then return end

	if state.augroup ~= -1 then
		pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
	end

	Action.close(state.action)
	Main.close(state.main)

	state.reset()
end

function _actions_handler.cycle_mode()
	state.lines = api.cycle_mode()
	M.refresh()
end

function _actions_handler.toggle_beast()
	state.lines = api.toggle_beast_only()
	M.refresh()
end

function _actions_handler.expand_at_cursor()
	local line = vim.api.nvim_get_current_line()
	local id = line:match("%[.+%] (%S+)")
	if not id then
		return
	end
	state.lines = api.toggle_expand(id)
	M.refresh()
end

-- =============================================================================
-- Controller
-- =============================================================================

local function render_state()
	Main.render(state.main, state.lines)
	Action.render(state.action)
end

local function layout_state()
	Main.layout(state.main)
	Action.layout(state.action, state.main)
end

local function mount_keymaps()
	for _, a in ipairs(config.cheatsheet.actions) do
		---@type string[]
		---@diagnostic disable-next-line: assign-type-mismatch
		local keys = type(a.keys) == "string" and { a.keys } or a.keys
		for _, key in ipairs(keys) do
			vim.keymap.set("n", key, actions[a.on_press], {
				buffer = state.main.buf,
				silent = true,
				nowait = true,
			})
		end
	end
end

local function mount_autocmds()
	state.augroup = vim.api.nvim_create_augroup("BeastKeyCheatsheet_" .. tostring(vim.loop.hrtime()), { clear = true })

	vim.api.nvim_create_autocmd("BufLeave", {
		group = state.augroup,
		buffer = state.main.buf,
		once = true,
		callback = function()
			actions.close()
		end,
	})

	vim.api.nvim_create_autocmd("WinEnter", {
		group = state.augroup,
		callback = function()
      -- stylua: ignore
			if state == nil or not state.is_valid() then return end
			local current = vim.api.nvim_get_current_win()
			if current ~= state.main.win then
				actions.close()
			end
		end,
	})

	vim.api.nvim_create_autocmd("VimResized", {
		group = state.augroup,
		callback = function()
      -- stylua: ignore
			if not state:is_valid() then return end
			layout_state()
		end,
	})
end

-- =============================================================================
-- Public
-- =============================================================================

function M.open()
	if state.is_valid() then
		vim.api.nvim_set_current_win(state.main.win)
		return
	end
	state.main = Main.create()
	state.action = Action.create(state.main)
	mount_keymaps()
	mount_autocmds()
	render_state()
end

function M.refresh()
	if not state:is_valid() then
		return
	end
	render_state()
end

return M
