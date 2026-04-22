local M = {}

---Get import path from spec
---@param spec table
---@return string|nil
local function maybe_import_path(spec)
	if spec.src ~= nil and spec.import ~= nil then
		vim.notify("Spec cannot have both 'src' and 'import' fields", vim.log.levels.ERROR, { title = "BeastVim" })
		return nil
	end
	return spec.import
end

---Check if a spec is valid (not empty)
---@param spec table
---@return boolean
local function is_valid_spec(spec)
	-- Empty table is not a valid spec
	if vim.tbl_isempty(spec) then
		return false
	end
	if spec.src ~= nil and spec.import ~= nil then
		vim.notify("Spec cannot have both 'src' and 'import' fields", vim.log.levels.ERROR, { title = "BeastVim" })
		return false
	end
	-- Must have either 'src' (plugin spec) or 'import' (import spec)
	return spec.src ~= nil or spec.import ~= nil
end

---Load plugin specs from a module path
---@param module_path string Module path (e.g., "beastvim.plugins")
---@return Beast.LazyLoader.PluginSpec[]
local function load_specs_from_module(module_path)
	local ok, result = pcall(require, module_path)
	if not ok then
		Toast.show(
			"Failed to load specs from " .. module_path .. ": " .. result,
			vim.log.levels.WARN,
			{ title = "BeastVim" }
		)
		return {}
	end

	-- Result should be a table of specs
	if type(result) ~= "table" then
		Toast.show("Module " .. module_path .. " did not return a table", vim.log.levels.ERROR, { title = "BeastVim" })
		return {}
	end

  -- Empty table means no specs
  -- stylua: ignore
  if vim.tbl_isempty(result) then return {} end

	-- Handle both array and single spec
	if vim.islist(result) then
		-- It's an array, filter out invalid specs
		local valid_specs = {}
		for _, spec in ipairs(result) do
			if is_valid_spec(spec) then
				table.insert(valid_specs, spec)
			end
		end
		return valid_specs
	else
		-- Single spec, validate it
		return is_valid_spec(result) and { result } or {}
	end
end

---Recursively expand import specs
---@param specs Beast.LazyLoader.PluginSpec[]
---@param processed? table<string, boolean> Track processed imports to avoid cycles
---@return Beast.LazyLoader.PluginSpec[]
function M.expand_imports(specs, processed)
	processed = processed or {}
	---@type Beast.LazyLoader.PluginSpec[]
	local expanded = {}

	for _, spec in ipairs(specs) do
		local import_path = maybe_import_path(spec)
		if import_path then
			-- Avoid circular imports
			if processed[import_path] then
				Toast.show("Circular import detected: " .. import_path, vim.log.levels.WARN, { title = "BeastVim" })
				goto continue
			end

			-- Check conditions
			if spec.enabled == false then
				goto continue
			end
			if spec.cond and not spec.cond() then
				goto continue
			end

			-- Mark as processed
			processed[import_path] = true

			-- Load specs from module
			local imported_specs = load_specs_from_module(import_path)

			-- Recursively expand nested imports
			local nested_expanded = M.expand_imports(imported_specs, processed)

			-- Add to result
			for _, nested_spec in ipairs(nested_expanded) do
				table.insert(expanded, nested_spec)
			end

			-- Add to result
			for _, nested_spec in ipairs(nested_expanded) do
				table.insert(expanded, nested_spec)
			end
		else
			-- Regular plugin spec, add directly
			table.insert(expanded, spec)
		end

		::continue::
	end

	return expanded
end

return M
