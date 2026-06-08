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

-- =============================================================================
-- Conflict tracking
-- =============================================================================
-- When two `set()` calls share the same (mode, lhs), the later one silently
-- overwrites the former in Neovim's keymap table. `M.managed` also collapses
-- to a single entry, so post-hoc duplicate scans (e.g. via
-- `nvim_get_keymap`) cannot detect the collision.
--
-- We catch it at set-time instead: every registration is recorded into
-- `M.conflicts[id]` with caller info. Any id whose history length > 1 is a
-- duplicate. A single deferred warning is emitted so the user knows to run
-- `:checkhealth beast.libs.key` for full details.
--
-- Buffer-local maps ARE recorded (so LSP `keys` like `<leader>ca` show up in
-- the prefix-conflict scan), but registrations from the same (source, line)
-- are deduped — the LSP attach handler attaching the same spec to many
-- buffers is not a conflict.
-- =============================================================================

---@class Beast.Keymap.CallSite
---@field source string  Source file path (from debug.getinfo)
---@field line integer   Line number of the call
---@field desc? string

---@class Beast.Keymap.Conflict
---@field lhs string     Original lhs as written (preserves `<leader>` etc.)
---@field mode string
---@field calls Beast.Keymap.CallSite[]

---@type table<string, Beast.Keymap.Conflict>
M.conflicts = {}

---@class Beast.Keymap.PrefixPair
---@field short_id string  id of the shorter (prefix) lhs
---@field long_id string   id of the longer lhs
---@field mode string

---@type table<string, Beast.Keymap.PrefixPair>
M.prefix_conflicts = {}

local conflict_notify_scheduled = false

local function schedule_conflict_notify()
	if conflict_notify_scheduled then return end
	conflict_notify_scheduled = true
	vim.schedule(function()
		local dups = 0
		for _, b in pairs(M.conflicts) do
			if #b.calls > 1 then dups = dups + 1 end
		end
		local prefixes = vim.tbl_count(M.prefix_conflicts)
		if dups + prefixes > 0 then
			local parts = {}
			if dups > 0 then parts[#parts + 1] = string.format("%d duplicate", dups) end
			if prefixes > 0 then parts[#parts + 1] = string.format("%d prefix", prefixes) end
			vim.notify(
				string.format(
					"Keymap conflicts detected (%s) \nRun `:checkhealth beast.libs.key` for details",
					table.concat(parts, ", ")
				),
				vim.log.levels.WARN,
				{ timeout = 10000, title = "beast.libs.key" }
			)
		end
		conflict_notify_scheduled = false
	end)
end

---Resolve the first user-land caller, skipping internal key/* frames and C frames
---(e.g. `__call` metamethod on `core` when invoked as `map(...)`).
---@return Beast.Keymap.CallSite
local function resolve_call_site(desc)
	for level = 2, 20 do
		local info = debug.getinfo(level, "Sl")
		if not info then break end
		local src = info.source or ""
		local is_c = info.what == "C" or src == "=[C]" or src:sub(1, 2) == "=["
		local is_internal = src:find("lua/beast/libs/key/", 1, true) ~= nil
		if not is_c and not is_internal and src ~= "" then
			return { source = src:gsub("^@", ""), line = info.currentline or 0, desc = desc }
		end
	end
	return { source = "?", line = 0, desc = desc }
end

---Scan existing managed maps in the same mode for a prefix relationship with
---`new_id` (termcode-normalized lhs `new_norm`). Records any new pair into
---`M.prefix_conflicts` keyed by "short_id\0long_id" (so the same pair isn't
---reported twice across set calls).
---@param new_id string
---@param new_norm string
---@param mode string
---@return boolean added Whether at least one new pair was recorded
local function scan_prefix(new_id, new_norm, mode)
	local added = false
	for other_id, other in pairs(M.conflicts) do
		if other_id ~= new_id and other.mode == mode then
			local other_norm = vim.api.nvim_replace_termcodes(other.lhs, true, true, true)
			local short_id, long_id
			if #other_norm < #new_norm and new_norm:sub(1, #other_norm) == other_norm then
				short_id, long_id = other_id, new_id
			elseif #new_norm < #other_norm and other_norm:sub(1, #new_norm) == new_norm then
				short_id, long_id = new_id, other_id
			end
			if short_id then
				local pair_key = short_id .. "\0" .. long_id
				if not M.prefix_conflicts[pair_key] then
					M.prefix_conflicts[pair_key] = { short_id = short_id, long_id = long_id, mode = mode }
					added = true
				end
			end
		end
	end
	return added
end

---@param id string
---@param km Beast.Keymap
local function record_call(id, km)
	local site = resolve_call_site(km.desc)
	local bucket = M.conflicts[id]
	local is_new = bucket == nil
	local dup_added = false

	if is_new then
		M.conflicts[id] = { lhs = km.lhs, mode = km.mode, calls = { site } }
	else
		-- Dedupe by (source, line): the same call site re-registering (e.g. an
		-- LSP `keys` entry attaching across many buffers) is not a conflict.
		local last = bucket.calls[#bucket.calls]
		if last.source == site.source and last.line == site.line then
			return
		end
		bucket.calls[#bucket.calls + 1] = site
		dup_added = true
	end

	local prefix_added = false
	if is_new then
		local norm = vim.api.nvim_replace_termcodes(km.lhs, true, true, true)
		prefix_added = scan_prefix(id, norm, km.mode)
	end

	if dup_added or prefix_added then
		schedule_conflict_notify()
	end
end

---Forget conflict history for an id (called from M.del and from tests/health).
---Also removes any prefix-conflict pairs that referenced this id.
---@param id string
function M.forget_conflict(id)
	M.conflicts[id] = nil
	for pair_key, pair in pairs(M.prefix_conflicts) do
		if pair.short_id == id or pair.long_id == id then
			M.prefix_conflicts[pair_key] = nil
		end
	end
end

-- =============================================================================
-- BeastKeysChanged
-- =============================================================================
-- A `User` autocommand fired (deferred via `vim.schedule`) whenever a managed
-- keymap is set, deleted, or relabeled. Carries `{ action, keys, buffer }` in
-- `data` so subscribers can react granularly.
--
-- Why an autocmd and not a direct call?
--   * `M.managed` is the single source of truth; multiple consumers may want
--     to react (cache invalidation, exporters, future tooling).
--   * Decoupled from any specific consumer — `core.lua` does not know who is
--     listening and does not need to.
--   * Consumers opt-in via their own setup (see lib-conventions.md §7).
--
-- Current subscribers
--   * `beast.libs.key.hint.index` — invalidates the prefix-tree cache so
--     keymaps registered at runtime (LSP attach, lazy-loaded plugins) appear
--     in the press-and-wait hint without restart.
--
-- ⚠ Keep this in sync when adding/removing consumers.
-- =============================================================================

---@param action 'keymap:set'|'keymap:del'|'keymap:label'
---@param keys Beast.Keymap
---@param buf? integer|boolean
local function emit_changed(action, keys, buf)
	-- Defer to avoid re-entrancy and batch rapid changes.
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
	M.forget_conflict(keys.id)
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

	-- Normalise buffer identity so downstream consumers (e.g. hint index) can
	-- determine which buffer this map lives on. `true` / `0` mean "current
	-- buffer" at set-time — resolve to the actual bufnr.
	if buffer == true or buffer == 0 then
		keys.buffer = vim.api.nvim_get_current_buf()
	elseif type(buffer) == "number" then
		keys.buffer = buffer
	end

	-- Store the full keymap object for later export
	M.managed[keys.id] = keys
	record_call(keys.id, keys)
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
			-- Label/group only: track in the registry for the hint index, but
			-- don't register an actual keymap with Neovim.
			M.managed[km.id] = km
			emit_changed(EVENTS.LBL, km, opts.buffer)
		end
		-- rhs == nil → label/group: skip (no mapping)
	end
end

return M
