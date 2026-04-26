local M = {}

--- Setup command trigger for a plugin
---@param plugin_spec Beast.Packer.PluginSpec Plugin spec with name and optional config
---@param commands string|string[] Command(s) to trigger on
---@param load_fn function Function to load the plugin
function M.setup(plugin_spec, commands, load_fn)
  -- Normalize to table
  -- stylua: ignore
  if type(commands) == "string" then commands = { commands } end

	for _, cmd in ipairs(commands) do
		vim.api.nvim_create_user_command(cmd, function(opts)
			-- Delete the fake command
			pcall(vim.api.nvim_del_user_command, cmd)

			-- Load the plugin (real command now available)
			-- Pass the command name that triggered the load
			load_fn(plugin_spec.name, { type = "cmd", detail = cmd })

			-- Re-execute the command with original args (scheduled to ensure plugin is loaded)
			vim.schedule(function()
				local args = opts.args or ""
				local full_cmd = args ~= "" and (cmd .. " " .. args) or cmd
        -- stylua: ignore
        local ok, err = pcall(function() vim.cmd(full_cmd) end)
				if not ok then
					vim.notify("Error executing " .. cmd .. ": " .. tostring(err), vim.log.levels.ERROR)
				end
			end)
		end, { nargs = "*", desc = "Lazy load " .. plugin_spec.name })
	end
end

return M
