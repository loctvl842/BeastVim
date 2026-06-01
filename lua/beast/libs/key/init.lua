local config = require("beast.libs.key.config")

local M = setmetatable({}, {
	__index = function(_, key)
		return require("beast.libs.key.core")[key]
	end,
})

M.safe_set = require("beast.libs.key.core").safe_set

M.managed = require("beast.libs.key.core").managed

---Convert a resolved keymap to which-key format
---@param keys Beast.Keymap
---@return table which-key spec
function M.to_which_key_spec(keys)
  if keys.rhs == nil then
    -- Treat as which-key-style label (no rhs): return minimal spec
    return { keys.lhs, mode = keys.mode, desc = keys.desc, group = keys.group }
  else
    return {
      keys.lhs,
      keys.rhs,
      mode = keys.mode,
      desc = keys.desc,
      -- Group of which-key is different from group of keymap
      group = nil,
      nowait = keys.nowait,
      remap = keys.remap,
      expr = keys.expr,
      silent = keys.silent,
    }
  end
end

---Get all managed keymaps in which-key format
---This is useful for registering keymaps with which-key
---@return table[] which-key specs
function M.to_which_key()
  local specs = {}

  for _, keys in pairs(M.managed) do
    if type(keys) == "table" and keys.lhs then
      table.insert(specs, M.to_which_key_spec(keys))
    end
  end

  return specs
end

---@param opts? Beast.Key.Config
function M.setup(opts)
	require("beast.libs.key.builtin")
	require("beast.libs.key.highlights")
	config.setup(opts)
	for _, spec in ipairs(config.mappings or {}) do
		M.safe_set(spec.mode or "n", spec[1], spec[2], spec)
	end
end

return M
