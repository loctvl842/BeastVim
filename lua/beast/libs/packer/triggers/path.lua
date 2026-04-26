local M = {}

--- Check if a path is within a directory
---@param file_path string The file path to check
---@param dir_pattern string The directory pattern (may contain ~ or be a glob)
---@return boolean
local function path_matches(file_path, dir_pattern)
	-- Expand ~ to home directory
	local expanded = vim.fn.expand(dir_pattern)

	-- If pattern contains wildcards, use glob matching
	if dir_pattern:match("[%*%?%[%]]") then
		return vim.fn.match(file_path, vim.fn.glob2regpat(expanded)) ~= -1
	end

	-- Otherwise, treat as a directory - check if file is within it
	-- Ensure directory path ends with /
	if not expanded:match("/$") then
		expanded = expanded .. "/"
	end

	-- Check if file_path starts with the directory
	return file_path:sub(1, #expanded) == expanded
end

--- Setup path pattern trigger for a plugin
---@param plugin_spec Beast.Packer.PluginSpec Plugin spec with name and optional config
---@param patterns string|string[] Path pattern(s) or directory(s) to trigger on
---@param load_fn function Function to load the plugin
function M.setup(plugin_spec, patterns, load_fn)
  -- Normalize to table
  -- stylua: ignore
  if type(patterns) == "string" then patterns = { patterns } end

	-- Track if already loaded to avoid redundant calls
	local loaded = false

	vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
		callback = function(ev)
			if loaded then
				return
			end

			local file_path = ev.match
			for _, pattern in ipairs(patterns) do
				if path_matches(file_path, pattern) then
					loaded = true
					load_fn(plugin_spec.name, { type = "path", detail = pattern })
					return
				end
			end
		end,
		desc = string.format("Lazy load %s on path pattern", plugin_spec.name),
	})
end

return M
