---@type Beast.Explorer.State
local state = require("beast.libs.explorer.state")
local config = require("beast.libs.explorer.config")

local M = {}

function M.mount()
  -- stylua: ignore
  if not state.view:is_valid() then return end

	local opts = { buffer = state.view.buf, silent = true, nowait = true }
	for lhs, action_name in pairs(config.mappings) do
		local ok, action = pcall(require, "beast.libs.explorer.actions." .. action_name)
		if not ok then
			error("Invalid action: " .. action_name)
		end
		vim.keymap.set("n", lhs, action.run, opts)
	end
end

return M
