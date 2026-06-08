---@class Beast.Autopairs.Pair
---@field close string                  -- closing character (== open for symmetric pairs)
---@field neigh_pattern string          -- 2-char Lua pattern matched against [before][after]
---@field register? { bs?: boolean, cr?: boolean }  -- reserved; bs/cr are global, here for future per-pair opt-out

---@class Beast.Autopairs.Modes
---@field insert boolean
---@field command boolean
---@field terminal boolean

---@class Beast.Autopairs.Config
---@field enabled boolean
---@field modes Beast.Autopairs.Modes
---@field pairs table<string, Beast.Autopairs.Pair>
---@field skip_next? string             -- Phase 2: Lua pattern matched against char-after
---@field skip_ts? string[]             -- Phase 2: treesitter capture names to veto inside
---@field skip_unbalanced boolean       -- Phase 2: skip when line has more closers than openers
---@field markdown boolean              -- Phase 2: smart ``` fence expansion

-- Neighborhood patterns mirror mini.pairs defaults:
--   * brackets: forbid pairing right after a backslash
--   * quotes:   forbid pairing adjacent to word-like text or escaped quotes
local BRACKET_NEIGH = "[^\\]."
local QUOTE_NEIGH = '[^%w\\"][^%w]'

---@type Beast.Autopairs.Config
local defaults = {
	enabled = true,
	modes = { insert = true, command = true, terminal = false },
	pairs = {
		["("] = { close = ")", neigh_pattern = BRACKET_NEIGH, register = { bs = true, cr = true } },
		["["] = { close = "]", neigh_pattern = BRACKET_NEIGH, register = { bs = true, cr = true } },
		["{"] = { close = "}", neigh_pattern = BRACKET_NEIGH, register = { bs = true, cr = true } },
		['"'] = { close = '"', neigh_pattern = QUOTE_NEIGH, register = { bs = true, cr = false } },
		["'"] = { close = "'", neigh_pattern = QUOTE_NEIGH, register = { bs = true, cr = false } },
		["`"] = { close = "`", neigh_pattern = QUOTE_NEIGH, register = { bs = true, cr = false } },
	},
	skip_next = nil,
	skip_ts = nil,
	skip_unbalanced = false,
	markdown = false,
}

---@type Beast.Autopairs.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param opts? Beast.Autopairs.Config
function methods.setup(opts)
	cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

--- Return the live config table. Read-only by convention — modules should
--- read fields via the public proxy (`config.skip_next`) instead.
---@return Beast.Autopairs.Config
function methods.get()
	return cfg
end

local M = setmetatable({}, {
	__index = function(_, key)
		if methods[key] ~= nil then
			return methods[key]
		end
		return cfg[key]
	end,
	__newindex = function(_, key, _)
		error(string.format("beast.autopairs.config is read-only; cannot assign '%s' directly. Use setup() instead.", tostring(key)), 2)
	end,
})

return M
