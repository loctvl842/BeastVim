local M = {}

--- Setup keymap trigger for a plugin
---@param plugin_spec Beast.Packer.PluginSpec Plugin spec with name and optional config
---@param keys_list Beast.KeymapSpec[]|Beast.KeymapSpec|string[]|string Key spec(s) to trigger on
---@param load_fn function Function to load the plugin
function M.setup(plugin_spec, keys_list, load_fn)
	-- Normalize to table
	if type(keys_list) == "string" then
		keys_list = { keys_list }
	end

	for _, key_spec in ipairs(keys_list) do
		-- Parse key spec
		local lhs, rhs, mode, desc, group
		if type(key_spec) == "string" then
			lhs = key_spec
			rhs = nil
			mode = "n"
			desc = "Lazy load " .. plugin_spec.name
			group = nil
		else
			lhs = key_spec[1]
			rhs = key_spec[2] -- Can be string (command) or function
			mode = key_spec.mode or "n"
			desc = key_spec.desc or ("Lazy load " .. plugin_spec.name)
			group = key_spec.group
		end

		-- Collect mapping options from the key spec
		local map_opts = { desc = desc, group = group }
		if type(key_spec) == "table" then
			if key_spec.nowait ~= nil then
				map_opts.nowait = key_spec.nowait
			end
			if key_spec.silent ~= nil then
				map_opts.silent = key_spec.silent
			end
			if key_spec.expr ~= nil then
				map_opts.expr = key_spec.expr
			end
			if key_spec.remap ~= nil then
				map_opts.remap = key_spec.remap
			end
			if key_spec.noremap ~= nil then
				map_opts.noremap = key_spec.noremap
			end
		end

		-- Set temporary keymap using Keys.safe_set (handles mode normalization automatically)
		Key.safe_set(mode, lhs, function()
			-- Delete the temporary keymap
			Key.safe_set(mode, lhs, false)

			-- Load the plugin
			-- Pass the key sequence that triggered the load
			load_fn(plugin_spec.name, { type = "keys", detail = lhs })

			-- Set up the real keymap if rhs was provided
			vim.schedule(function()
				if rhs then
					Key.safe_set(mode, lhs, rhs, map_opts)
					-- Execute the mapping
					if type(rhs) == "function" then
						rhs()
					else
						-- It's a key sequence string (e.g., "<cmd>Neotree toggle<cr>")
						local keys = vim.api.nvim_replace_termcodes(rhs, true, true, true)
						vim.api.nvim_feedkeys(keys, "m", false)
					end
				else
					-- No rhs provided, just re-trigger the key
					local keys = vim.api.nvim_replace_termcodes(lhs, true, true, true)
					vim.api.nvim_feedkeys(keys, "m", false)
				end
			end)
		end, map_opts)
	end
end

return M
