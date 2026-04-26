local M = {}

--- Setup filetype trigger for a plugin
---@param plugin_spec Beast.Packer.PluginSpec Plugin spec with name and optional config
---@param filetypes string|string[] Filetype(s) to trigger on
---@param load_fn function Function to load the plugin
function M.setup(plugin_spec, filetypes, load_fn)
  -- Normalize to table
  -- stylua: ignore
  if type(filetypes) == "string" then filetypes = { filetypes } end

	-- Track if already loaded to avoid redundant calls
	local loaded = false

	vim.api.nvim_create_autocmd("FileType", {
		pattern = filetypes,
		callback = function(ev)
			if loaded then
				return
			end
			loaded = true
			-- Pass the filetype that triggered the load
			load_fn(plugin_spec.name, { type = "filetype", detail = ev.match })
		end,
		desc = string.format("Lazy load %s on filetype", plugin_spec.name),
	})
end

return M
