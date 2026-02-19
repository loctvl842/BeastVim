---@class Beast.KeymapBase
---@field group? string Label for keymap
---@field has? string|string[] LSP capability check
---@field desc? string
---@field buffer? integer|boolean
---@field noremap? boolean
---@field remap? boolean
---@field expr? boolean
---@field nowait? boolean
---@field silent? boolean
---@field replace_keycodes? boolean
---@field unique? boolean
---@field script? boolean

---@class Beast.KeymapSpec: Beast.KeymapBase
---@field [1] string lhs (left-hand side)
---@field [2]? string|function rhs (right-hand side)
---@field mode? string|string[]

---@class Beast.Keymap: Beast.KeymapBase
---@field lhs string
---@field rhs? string|function
---@field mode string
---@field id string unique identifier for this keymap

-- stylua: ignore
local M = setmetatable({}, { __call = function(m, ...) return m.safe_set(...) end })

local EVENTS = {
	SET = "keymap:set",
	DEL = "keymap:del",
	LBL = "keymap:label",
}

M.managed = {}

-- Internal: emit a User autocommand when managed keys change, this is needed to attach new keys to which-key.nvim
---@param action 'keymap:set'|'keymap:del'|'keymap:label'
---@param keys Beast.Keymap
---@param buf? integer|boolean
local function emit_changed(action, keys, buf)
	-- Defer to avoid re-entrancy and batch rapid changes
	vim.schedule(function()
		pcall(vim.api.nvim_exec_autocmds, "User", {
			pattern = "BeastKeysChanged",
			data = { action = action, keys = keys, buffer = buf },
		})
	end)
end

---Parse Spec -> Base
---@param value Beast.KeymapSpec
---@param mode? string
---@return Beast.Keymap
local function parse(value, mode)
	local ret = vim.deepcopy(value) --[[@as Beast.Keymap]]

	ret.lhs = ret[1] or ""
	ret.rhs = ret[2]
	ret[1] = nil
	ret[2] = nil
	ret.mode = mode or "n"

	-- Create unique ID using termcodes for special keys
	ret.id = vim.api.nvim_replace_termcodes(ret.lhs, true, true, true) .. " (" .. ret.mode .. ")"

	return ret
end

local skip = { mode = true, id = true, rhs = true, lhs = true, has = true, group = true }

---@param keys Beast.KeymapBase
---@return table opts Options suitable for vim.keymap.set
function M.opts(keys)
	local opts = {}

	for k, v in pairs(keys) do
		if type(k) ~= "number" and not skip[k] then
			opts[k] = v
		end
	end

	return opts
end

---Delete a keymap and unmark it as managed
---@param keys Beast.Keymap
---@param buffer? integer|boolean Buffer number for buffer-local mapping
function M.del(keys, buffer)
	local ok, _ = pcall(vim.keymap.del, keys.mode, keys.lhs, { buffer = buffer })
	M.managed[keys.id] = nil
	emit_changed(EVENTS.DEL, keys, buffer)
	return ok
end

---Set a keymap and mark it as managed
---@param keys Beast.Keymap
---@param buffer? integer|boolean Buffer number for buffer-local mapping
function M.set(keys, buffer)
  -- stylua: ignore
  if not keys.rhs then return end

	local opts = M.opts(keys)
	if buffer ~= nil then
		opts.buffer = buffer
	end
	opts.silent = opts.silent ~= false -- default to silent

	vim.keymap.set(keys.mode, keys.lhs, keys.rhs, opts)

	-- Store the full keymap object for later export
	M.managed[keys.id] = keys
	emit_changed(EVENTS.SET, keys, buffer)
end

---Safely set or delete a keymap across modes
---@param mode string|string[] Modes (e.g. "n" or {"n","v"} or "nvo")
---@param lhs string
---@param rhs string|function
---@param opts? Beast.KeymapBase
function M.safe_set(mode, lhs, rhs, opts)
	opts = opts or {}
	opts.desc = opts.desc or ""

	-- Create keymap spec template
	---@type Beast.KeymapSpec
	local spec = { lhs, rhs, mode = mode }
  -- stylua: ignore
  for k, v in pairs(opts) do spec[k] = v end

	local modes
	if type(mode) == "table" then
		modes = mode --[[@as string[] ]]
	elseif type(mode) == "string" and #mode > 1 then
		modes = {}
		for m in mode:gmatch(".") do
			table.insert(modes, m)
		end
	else
		modes = {
			mode --[[@as string]],
		}
	end

	for _, m in ipairs(modes) do
		local km = parse(spec, m)
		if rhs == vim.NIL or rhs == false then
			M.del(km, opts.buffer)
		elseif rhs ~= nil then
			M.set(km, opts.buffer)
		else
			-- Label/group only: track for exporters (e.g., which-key), but don't set a mapping
			M.managed[km.id] = km
			emit_changed(EVENTS.LBL, km, opts.buffer)
		end
		-- rhs == nil → label/group: skip (no mapping)
	end
end

return M
