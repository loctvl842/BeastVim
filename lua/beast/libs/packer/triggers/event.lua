local M = {}

--- Setup autocmd trigger for a plugin
---@param plugin_spec Beast.Packer.PluginSpec Plugin spec with name and optional config
---@param events string|string[] Event(s) to trigger on
---@param load_fn function Function to load the plugin
function M.setup(plugin_spec, events, load_fn)
  -- Normalize to table
  -- stylua: ignore
  if type(events) == "string" then events = { events } end

	vim.api.nvim_create_autocmd(events, {
		once = true, -- Self-destruct after firing
		callback = function(ev)
			-- Pass the event name that triggered the load
			load_fn(plugin_spec.name, { type = "event", detail = ev.event })
		end,
	})
end

return M
