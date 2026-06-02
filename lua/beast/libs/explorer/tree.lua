-- =============================================================================
-- Node
-- =============================================================================

---@class Beast.Explorer.Node
---@field path       string
---@field name       string
---@field type       "file"|"directory"|"link"|"unknown"|string
---@field dir        boolean
---@field hidden     boolean
---@field open       boolean
---@field expanded   boolean
---@field depth      integer
---@field last       boolean
---@field git_status? Beast.Explorer.GitStatus
---@field children   table<string, string>
---@field parent?    string
local Node = setmetatable({}, {
	__call = function(t, ...)
		return t:new(...)
	end,
})
Node.__index = Node

---@class Beast.Explorer.NodeOpts
---@field open? boolean
---@field expanded? boolean
---@field depth? integer
---@field last? boolean
---@field git_status? Beast.Explorer.GitStatus

---@param path string
---@param name string
---@param ftype "file"|"directory"|"link"|"unknown"|string
---@param parent? Beast.Explorer.Node
---@param opts? Beast.Explorer.NodeOpts
---@return Beast.Explorer.Node
function Node:new(path, name, ftype, parent, opts)
	opts = opts or {}

	local is_dir = ftype == "directory" or (ftype == "link" and vim.fn.isdirectory(path) == 1)

	return setmetatable({
		path = path,
		name = name,
		type = ftype,
		dir = is_dir,
		hidden = name:sub(1, 1) == ".",
		open = opts.open or false,
		expanded = opts.expanded or false,
		depth = opts.depth or (parent and parent.depth + 1 or 0),
		last = opts.last or false,
		git_status = opts.git_status,
		children = {},
		parent = parent and parent.path or nil,
	}, Node)
end

-- =============================================================================
-- Tree
-- =============================================================================

---@class Beast.Explorer.FlatCacheEntry
---@field version integer
---@field list Beast.Explorer.Node[]?

---@class Beast.Explorer.FlatOpts
---@field show_hidden boolean

---@class Beast.Explorer.Tree
---@field root Beast.Explorer.Node
---@field nodes table<string, Beast.Explorer.Node>
---@field version integer
---@field _flat_cache table<boolean, Beast.Explorer.FlatCacheEntry>
local M = setmetatable({}, {
	__call = function(t, ...)
		return t:new(...)
	end,
})
M.__index = M

local state = require("beast.libs.explorer.state")
local watch = require("beast.libs.explorer.watch")

local uv = vim.uv or vim.loop

-- =============================================================================
-- Utils
-- =============================================================================

---@param path string
---@return string
local function norm(path)
	return (vim.fn.fnamemodify(path, ":p"):gsub("/$", ""))
end

---@param tree Beast.Explorer.Tree
---@param path string
local function remove_subtree(tree, path)
	local node = tree.nodes[path]
	if not node then
		return
	end

	for _, child_path in pairs(node.children) do
		remove_subtree(tree, child_path)
	end

	tree.nodes[path] = nil
end

---@param parent Beast.Explorer.Node
---@param name string
---@param ftype "file"|"directory"|"link"|"unknown"|string
---@return Beast.Explorer.Node
function M:ensure_child(parent, name, ftype)
	local existing_path = parent.children[name]
	if existing_path then
		local existing = self.nodes[existing_path]
		if existing then
			return existing
		end
	end

	local path = parent.path .. "/" .. name
	local node = Node(path, name, ftype, parent)

	-- Stamp git status from the cached maps (if available). Uses the same
	-- resolver as git.apply so untracked/ignored directory entries propagate
	-- down to newly-materialized descendants on expand.
	if state.git.status then
		node.git_status = require("beast.libs.explorer.git").resolve(path, parent.path)
	end

	parent.children[name] = path
	self.nodes[path] = node

	return node
end

-- =============================================================================
-- Lifecycle
-- =============================================================================

---@param cwd string
---@return Beast.Explorer.Tree
function M:new(cwd)
	cwd = norm(cwd)

	local root = Node(cwd, vim.fn.fnamemodify(cwd, ":t"), "directory", nil, {
		open = true,
		depth = -1,
		last = true,
	})

	return setmetatable({
		root = root,
		nodes = {
			[root.path] = root,
		},
		version = 0,
		_flat_cache = {
			[false] = { version = -1, list = nil },
			[true] = { version = -1, list = nil },
		},
	}, self)
end

function M:_touch()
	self.version = self.version + 1
end

-- =============================================================================
-- Tree expansion / refresh
-- =============================================================================

---@param node Beast.Explorer.Node
function M:expand(node)
	if not node.dir or node.expanded then
		return
	end

	local fs = uv.fs_scandir(node.path)
	if not fs then
		return
	end

	---@type table<string, boolean>
	local found = {}
	local changed = false

	while true do
		local name, ftype = uv.fs_scandir_next(fs)
		if not name then
			break
		end

		ftype = ftype or "unknown"
		found[name] = true

		if not node.children[name] then
			self:ensure_child(node, name, ftype)
			changed = true
		else
			local child_path = node.children[name]
			local child = self.nodes[child_path]

			if child then
				local is_dir = ftype == "directory" or (ftype == "link" and vim.fn.isdirectory(child_path) == 1)

				if child.type ~= ftype or child.dir ~= is_dir then
					child.type = ftype
					child.dir = is_dir
					changed = true
				end
			end
		end
	end

	for name, child_path in pairs(node.children) do
		if not found[name] then
			remove_subtree(self, child_path)
			node.children[name] = nil
			changed = true
		end
	end

	node.expanded = true
	watch.watch(node.path)

	if changed then
		self:_touch()
	end
end

--- Recursively clear `expanded` and stop watchers for a node and all its descendants.
--- Also clears `git_status`. Does NOT touch `open` (that's a UI toggle, not a scan flag).
---@param node Beast.Explorer.Node
---@return boolean changed  true if any node was actually expanded
function M:unwatch_subtree(node)
	local changed = false

	for _, child_path in pairs(node.children) do
		local child = self.nodes[child_path]
		if child then
			if self:unwatch_subtree(child) then
				changed = true
			end
		end
	end

	if node.expanded then
		node.expanded = false
		watch.unwatch(node.path)
		changed = true
	end

	return changed
end

---@param path string
function M:refresh(path)
	path = norm(path)

	local node = self.nodes[path]
	if not node then
		return
	end

	if self:unwatch_subtree(node) then
		self:_touch()
	end
end

---@param path? string
function M:collapse_all(path)
	local changed = false

	if not path then
		for _, node in pairs(self.nodes) do
			if node.dir and node.open then
				node.open = false
				changed = true
			end
		end

		if not self.root.open then
			self.root.open = true
			changed = true
		end

		if changed then
			self:_touch()
		end

		return
	end

	path = norm(path)

	local base = self.nodes[path]
	if not base or not base.dir then
		return
	end

	local prefix = base.path .. "/"

	for node_path, node in pairs(self.nodes) do
		if node.dir and node.open and node_path:sub(1, #prefix) == prefix then
			node.open = false
			changed = true
		end
	end

	if changed then
		self:_touch()
	end
end

-- =============================================================================
-- Navigation
-- =============================================================================

---@param path string
---@return Beast.Explorer.Node
function M:find(path)
	path = norm(path)

	local existing = self.nodes[path]
	if existing then
		return existing
	end

	local root_path = self.root.path

	if path ~= root_path and path:sub(1, #root_path + 1) ~= root_path .. "/" then
		error("Path must live inside the tree root: " .. path)
	end

	if path == root_path then
		return self.root
	end

	local rel = path:sub(#root_path + 2)
	local parts = vim.split(rel, "/", { plain = true })

	local node = self.root

	for i, part in ipairs(parts) do
		local cur = root_path .. "/" .. table.concat(parts, "/", 1, i)
		local ftype = vim.fn.isdirectory(cur) == 1 and "directory" or "file"

		node = self:ensure_child(node, part, ftype)
	end

	return node
end

---@param path string
function M:open(path)
	if vim.fn.isdirectory(path) ~= 1 then
		path = vim.fs.dirname(path)
	end

	local node = self:find(path)
	local changed = false

	while node and node.depth >= 0 do
		if not node.open then
			node.open = true
			changed = true
		end

		node = self.nodes[node.parent]
	end

	if changed then
		self:_touch()
	end
end

---@param path string
function M:close(path)
	if vim.fn.isdirectory(path) ~= 1 then
		path = vim.fs.dirname(path)
	end

	local node = self:find(path)
	if not node then
		return
	end

	local changed = false

	if node.open then
		node.open = false
		changed = true
	end

	if node.expanded then
		self:unwatch_subtree(node)
		changed = true
	end

	if changed then
		self:_touch()
	end
end

---@param path string
function M:toggle(path)
	if vim.fn.isdirectory(path) ~= 1 then
		path = vim.fs.dirname(path)
	end

	local node = self:find(path)
	if not node then
		return
	end

	if node.open then
		self:close(path)
	else
		self:collapse_all(path)
		self:open(path)
	end
end

-- =============================================================================
-- Traversal
-- =============================================================================

---@param node Beast.Explorer.Node
---@param fn fun(node: Beast.Explorer.Node): boolean?
function M:walk(node, fn)
	local children = vim.tbl_values(node.children)

	table.sort(children, function(path_a, path_b)
		local node_a = self.nodes[path_a]
		local node_b = self.nodes[path_b]

		if node_a.dir ~= node_b.dir then
			return node_a.dir
		end

		return node_a.name:lower() < node_b.name:lower()
	end)

	for i, child_path in ipairs(children) do
		local child = self.nodes[child_path]

		if child then
			child.last = i == #children

			local descend = fn(child)

			if descend ~= false and child.dir and child.open then
				if not child.expanded then
					self:expand(child)
				end

				self:walk(child, fn)
			end
		end
	end
end

-- =============================================================================
-- Flat list
-- =============================================================================

---@param opts Beast.Explorer.FlatOpts
---@return Beast.Explorer.Node[]
function M:flat(opts)
	local root = self.root

	if not root.expanded then
		self:expand(root)
	end

	local cache = self._flat_cache[opts.show_hidden]
	if cache and cache.version == self.version and cache.list then
		return cache.list
	end

	---@type Beast.Explorer.Node[]
	local list = {}

	self:walk(root, function(node)
		if node.hidden and not opts.show_hidden then
			return false
		end

		list[#list + 1] = node
	end)

	self._flat_cache[opts.show_hidden] = {
		version = self.version,
		list = list,
	}

	return list
end

return M
