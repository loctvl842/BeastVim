local config = require("beast.libs.explorer.config")
local state = require("beast.libs.explorer.state")

local M = {}

local mounted = false

function M.mount()
	if mounted then
		return
	end
	mounted = true
  -- stylua: ignore
  if not state.view:is_valid() then return end

	local opts = { buffer = state.view.buf, silent = true, nowait = true }
	for lhs, action_name in pairs(config.mappings) do
		local ok, action = pcall(require, "beast.libs.explorer.actions." .. action_name)
		if not ok then
			error("Invalid action: " .. action_name)
		end
		vim.keymap.set("n", lhs, action.run, opts)
		if action.run_visual then
			vim.keymap.set("v", lhs, action.run_visual, opts)
		end
	end

	-- Jumplist navigation would replace the explorer with whatever buffer the
	-- jump points at, breaking the dedicated tree window. Block it. (<Tab> is
	-- <C-i>, so disabling it here keeps Tab inert in the explorer too.)
	vim.keymap.set("n", "<C-o>", "<Nop>", opts)
	vim.keymap.set("n", "<C-i>", "<Nop>", opts)
end

return M
