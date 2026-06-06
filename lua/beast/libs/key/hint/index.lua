local core = require("beast.libs.key.core")

local M = {}

-- =============================================================================
-- Key utilities
-- =============================================================================

---Split an lhs into a list of normalised key tokens via keytrans+termcodes.
---e.g. "<leader>fa" with mapleader=" " → { " ", "f", "a" }
---     "<C-w>h"                         → { "<C-W>", "h" }
---@param lhs string
---@return string[]
function M.split_keys(lhs)
	local termcoded = vim.api.nvim_replace_termcodes(lhs, true, true, true)
	local tokens = {}
	local i = 1
	local n = #termcoded
	while i <= n do
		local c = termcoded:sub(i, i)
		-- Special keys begin with 0x80 (K_SPECIAL) and span 3 bytes.
		if c == "\x80" then
			local raw = termcoded:sub(i, i + 2)
			table.insert(tokens, vim.fn.keytrans(raw))
			i = i + 3
		else
			table.insert(tokens, vim.fn.keytrans(c))
			i = i + 1
		end
	end
	return tokens
end

---Translate a single key from getcharstr() to canonical form (e.g. "<Esc>").
---@param key string
---@return string
function M.key_label(key)
	return vim.fn.keytrans(key)
end

-- =============================================================================
-- Index (prefix tree)
-- =============================================================================

---@class Beast.Key.Hint.Node
---@field children table<string, Beast.Key.Hint.Node>
---@field keymap? Beast.Keymap   -- present at leaves
---@field group? string          -- group label if any
---@field key string             -- the single key segment that leads here

---@type table<string, Beast.Key.Hint.Node>?  -- mode → tree root
local cache = nil

local function new_node(key)
	return { children = {}, key = key or "" }
end

---@return table<string, Beast.Key.Hint.Node>
function M.build_index()
	---@type table<string, Beast.Key.Hint.Node>
	local roots = {}

	for _, km in pairs(core.managed) do
		if type(km) == "table" and km.lhs and km.mode then
			local root = roots[km.mode]
			if not root then
				root = new_node()
				roots[km.mode] = root
			end
			local segs = M.split_keys(km.lhs)
			local node = root
			for _, seg in ipairs(segs) do
				local child = node.children[seg]
				if not child then
					child = new_node(seg)
					node.children[seg] = child
				end
				node = child
			end
			-- Attach the km to the node when it has either an executable rhs OR a
			-- description worth surfacing. Label-only entries that contribute
			-- ONLY a group (intermediate prefix labels) are handled via
			-- `node.group` below — keeping them off the keymap field so the
			-- group highlight path (BeastKeyHintGroup) still fires.
			if km.rhs ~= nil or (km.desc and km.desc ~= "") then
				node.keymap = km
			end
			if km.group then
				node.group = km.group
			end
		end
	end

	return roots
end

local function get_index()
	if not cache then
		cache = M.build_index()
	end
	return cache
end

function M.invalidate()
	cache = nil
end

---Modes that should fall back to a sibling mode in the index.
---Visual `x` mappings are also commonly registered as `v` (visual+select).
local MODE_FALLBACK = { x = "v", s = "v" }

---Walk the tree following a sequence of translated keys.
---@param mode string
---@param segs string[]
---@return Beast.Key.Hint.Node?
function M.walk(mode, segs)
	local idx = get_index()
	local root = idx[mode] or idx[MODE_FALLBACK[mode] or mode]
	if not root then
		return nil
	end
	local node = root
	for _, seg in ipairs(segs) do
		node = node.children and node.children[seg]
		if not node then
			return nil
		end
	end
	return node
end

---Returns true if any descendant (or this node) holds a keymap reachable from bufnr.
---@param node Beast.Key.Hint.Node
---@param bufnr integer
---@return boolean
function M.reachable(node, bufnr)
	if node.keymap then
		local b = node.keymap.buffer
		if b == nil or b == false then
			return true
		end
		if type(b) == "number" then
			return b == bufnr
		end
	end
	for _, c in pairs(node.children) do
		if M.reachable(c, bufnr) then
			return true
		end
	end
	return false
end

---Filter children of a node to those that are reachable from the current buffer.
---@param node Beast.Key.Hint.Node
---@param bufnr integer
---@return { key: string, child: Beast.Key.Hint.Node }[]
function M.visible_children(node, bufnr)
	local out = {}
	for key, child in pairs(node.children) do
		if M.reachable(child, bufnr) then
			table.insert(out, { key = key, child = child })
		end
	end
	-- Sort:
	--   1. By group label first (folder nodes use `child.group`, leaf
	--      nodes use `child.keymap.group`). This clusters every row that
	--      shares a group — e.g. all "Git" rows together — which is one of
	--      our advantages over which-key.nvim, where groups are inferred
	--      from desc prefixes only.
	--   2. Rows with no group sink to the bottom.
	--   3. Within a group, sort alphabetically by key.
	table.sort(out, function(a, b)
		local ag = a.child.group or (a.child.keymap and a.child.keymap.group) or ""
		local bg = b.child.group or (b.child.keymap and b.child.keymap.group) or ""
		if ag ~= bg then
			if ag == "" then
				return false
			end
			if bg == "" then
				return true
			end
			return ag < bg
		end
		return a.key < b.key
	end)
	return out
end

return M
