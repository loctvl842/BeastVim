-- stylua: ignore start
local state             = require("beastvim.libs.lazy_loader.state")
local import            = require("beastvim.libs.lazy_loader.import")
-- stylua: ignore end

local M = {}

-- ================================
-- Utils
-- ================================
local function extract_name_from_src(src)
	if type(src) ~= "string" or src == "" then
		error("extract_name_from_src: src must be a non-empty string")
	end

	-- Remove .git suffix
	local name = src:gsub("%.git$", "")

	-- Extract last segment after /
	name = name:match("[^/]+$") or ""

	if name == "" then
		error("extract_name_from_src: could not extract name from src: " .. src)
	end

	return name
end

local function normalize_spec(spec)
	if not spec.src then
		error("normalize_spec: spec must have a src field")
	end

	-- If name is already provided, use it
	if spec.name and spec.name ~= "" then
		return spec
	end

	-- Extract name from src
	spec.name = extract_name_from_src(spec.src)

	return spec
end

-- ================================
-- Methods
-- ================================

--- Setup lazy loader with plugin specs
---@param specs Beast.LazyLoader.PluginSpec[] List of plugin specs
function M.setup(specs)
	-- Step 0: Expand imports (plugin discovery)
	specs = import.expand_imports(specs)
	-- Filter those with cond == false
	specs = vim.tbl_filter(function(spec)
		return spec.cond == nil or spec.cond()
	end, specs)

	-- Step 1: Normalize all specs to ensure they have names
	for i, spec in ipairs(specs) do
		specs[i] = normalize_spec(spec)
	end

	-- Step 2: Run init functions for all plugins
	for _, spec in ipairs(specs) do
		if spec.init then
			local ok, err = pcall(function()
				state.profile(spec.name, "config_ms", spec.init)
			end)
			if not ok then
				vim.notify(
					"Error in init for " .. spec.name .. ": " .. tostring(err),
					vim.log.levels.ERROR,
					{ title = "BeastVim" }
				)
			end
		end
	end

	-- Step 3: Collect all specs and build vim.pack specs
	local vim_pack_specs = {}
	local lazy_specs = {}
	local eager_specs = {}
	local manual_specs = {}

	for _, spec in ipairs(specs) do
		-- Add to vim.pack list with name so vim.pack uses our extracted name
		table.insert(vim_pack_specs, { src = spec.src, name = spec.name })

		-- Register the plugin
		table.insert(state.lazy_plugins, spec)

		-- Classify as lazy, eager, or manual
		-- lazy = false (explicitly) → eager
		-- lazy = { ... } (table)    → lazy with triggers
		-- lazy = nil (not set)      → manual (no automatic loading)
		if spec.lazy == false then
			table.insert(eager_specs, spec)
		elseif type(spec.lazy) == "table" then
			table.insert(lazy_specs, spec)
		else -- lazy is nil - manual loading only
			table.insert(manual_specs, spec)
		end
	end

  -- Setup autocmd to track vim.pack operations and show UI
  vim.api.nvim_create_autocmd("PackChangedPre", {
    callback = function(ev)
      local kind = ev.data.kind -- "install", "update", or "delete"
      local name = ev.data.spec.name

      -- Start tracking operation AFTER user confirms
      if kind == "install" or kind == "update" then
        local was_active = state.has_active_operations
        state.start_operation(name, kind)
        -- Only open/refresh UI once when the batch starts
        if not was_active then
          -- TODO: continue here
          -- ui.show()
        end
      end
    end
  })
end

return M
