---@class Beast.Explorer.Node
---@field path       string   absolute path
---@field name       string   basename
---@field type       "file"|"directory"|"link"|"unknown"
---@field dir        boolean  true when this entry is (or resolves to) a directory
---@field hidden     boolean  name starts with "."
---@field open       boolean  directory: user wants it expanded
---@field expanded   boolean  directory: children have been scanned from disk
---@field depth      integer  0 = immediate children of the cwd root
---@field last       boolean  last sibling in its parent — used for tree-line drawing
---@field git_status? string
---@field children   table<string, string>  name -> path
---@field parent?    string  absolute path of parent

---@class Beast.Explorer.FlatCacheEntry
---@field version integer
---@field list Beast.Explorer.Node[]?

---@class Beast.Explorer.Tree
---@field root Beast.Explorer.Node
---@field nodes table<string, Beast.Explorer.Node>  path -> node
---@field version integer
---@field _flat_cache table<boolean, Beast.Explorer.FlatCacheEntry>
local M = setmetatable({}, {
	__call = function(t, ...)
		return t:new(...)
	end,
})
M.__index = M

local uv = vim.uv or vim.loop

-- =============================================================================
-- Utils
-- =============================================================================

--- Normalize a path: absolute, no trailing slash.
---@param path string
---@return string
local function norm(path)
	return (vim.fn.fnamemodify(path, ":p"):gsub("/$", ""))
end

--- Remove `path` and all descendants from the node index.
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

--- Return-or-create the child of `parent` identified by `name` / `ftype`.
---@param tree   Beast.Explorer.Tree
---@param parent Beast.Explorer.Node
---@param name   string
---@param ftype  "file"|"directory"|"link"|"unknown"|string
---@return Beast.Explorer.Node
local function ensure_child(tree, parent, name, ftype)
	local existing_path = parent.children[name]
	if existing_path then
		---@type Beast.Explorer.Node
		local existing = tree.nodes[existing_path]
		if existing then
			return existing
		end
	end

	local path = parent.path .. "/" .. name
	local is_dir = ftype == "directory" or (ftype == "link" and vim.fn.isdirectory(path) == 1)

	---@type Beast.Explorer.Node
	local node = {
		path = path,
		name = name,
		type = ftype,
		dir = is_dir,
		hidden = name:sub(1, 1) == ".",
		open = false,
		expanded = false,
		depth = parent.depth + 1,
		last = false,
		git_status = nil,
		children = {},
		parent = parent.path,
	}

	parent.children[name] = path
	tree.nodes[path] = node
	return node
end

-- =============================================================================
-- Lifecycle
-- =============================================================================

---@param cwd string
---@return Beast.Explorer.Tree
function M:new(cwd)
	cwd = norm(cwd)

	---@type Beast.Explorer.Node
	local root = {
		path = cwd,
		name = vim.fn.fnamemodify(cwd, ":t"),
		type = "directory",
		dir = true,
		hidden = false,
		open = true,
		expanded = false,
		depth = -1,
		last = true,
		git_status = nil,
		children = {},
		parent = nil,
	}

	return setmetatable({
		root = root,
		nodes = { [root.path] = root },
		version = 0,
		_flat_cache = {
			[false] = { version = -1, list = nil },
			[true] = { version = -1, list = nil },
		},
	}, self)
end

--- Mark tree state as changed.
function M:_touch()
	self.version = self.version + 1
end

-- =============================================================================
-- Tree expansion / refresh
-- =============================================================================

--- Scan `node`'s directory and (re)populate its children from disk.
--- Stale entries (deleted files) are pruned from the node index.
---@param node Beast.Explorer.Node
function M:expand(node)
  -- stylua: ignore
	if not node.dir or node.expanded then return end

	local fs = uv.fs_scandir(node.path)
	if not fs then
		return
	end

	---@type table<string, boolean>
	local found = {}
	local changed = false

	while true do
		local name, ftype = uv.fs_scandir_next(fs)
    -- stylua: ignore
		if not name then break end

		ftype = ftype or "unknown"
		found[name] = true

		if not node.children[name] then
			ensure_child(self, node, name, ftype)
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
	if changed then
		self:_touch()
	end
end

---@param path string
function M:refresh(path)
	path = norm(path)

	local node = self.nodes[path]
	if not node then
		return
	end

	local changed = false

	local function clear(n)
		if n.expanded then
			n.expanded = false
			changed = true
		end
		if n.git_status ~= nil then
			n.git_status = nil
		end
		for _, child_path in pairs(n.children) do
			local child = self.nodes[child_path]
			if child then
				clear(child)
			end
		end
	end

	clear(node)

	if changed then
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

--- Return the node for `path`, creating ancestor nodes if absent.
---@param path string
---@return Beast.Explorer.Node
function M:find(path)
	path = norm(path)

	local existing = self.nodes[path]
	if existing then
		return existing
	end

	local root_path = self.root.path
	if path ~= root_path and path:sub(1, #root_path + 1) ~= (root_path .. "/") then
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
		node = ensure_child(self, node, part, ftype)
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
		node.expanded = false
		changed = true
	end

	if changed then
		self:_touch()
	end
end

--- Toggle the open state of `path` to a folder.
--- If it's a file, toggle its parent directory.
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
			child.last = (i == #children)

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
-- Flat list (cached)
-- =============================================================================

---@param opts { show_hidden: boolean }
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
