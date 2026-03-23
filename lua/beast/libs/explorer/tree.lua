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
---@field git_status? string  two-char XY porcelain code, set by Tree.flat()
---@field children  table<string, string>  name -> path
---@field parent?   string absolute path of parent

---@class Beast.Explorer.Tree
---@field root  Beast.Explorer.Node     virtual root (path = "")
---@field nodes table<string, Beast.Explorer.Node>  path → node index
local M = setmetatable({}, {
	__call = function(t, ...)
		return t:new(...)
	end,
})
M.__index = M

local uv = vim.uv or vim.loop

-- =============================================================================
-- UTILS
-- =============================================================================

--- Normalise a path: absolute, no trailing slash.
---@param path string
---@return string
local function norm(path)
	return (vim.fn.fnamemodify(path, ":p"):gsub("/$", ""))
end

--- Return-or-create the child of `parent` identified by `name` / `ftype`.
---@param tree   Beast.Explorer.Tree
---@param parent Beast.Explorer.Node
---@param name   string
---@param ftype  string
---@return Beast.Explorer.Node
local function ensure_child(tree, parent, name, ftype)
	if parent.children[name] then
    local path = parent.children[name]
		return tree.nodes[path]
	end

	local path = parent.path == "" and ("/" .. name) or (parent.path .. "/" .. name)
	local is_dir = ftype == "directory" or (ftype == "link" and vim.fn.isdirectory(path) == 1)
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
-- TREE
-- =============================================================================

---@param cwd string
---@return Beast.Explorer.Tree
function M:new(cwd)
	cwd = norm(cwd)
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
		children = {},
		parent = nil,
	}
	return setmetatable({ root = root, nodes = { [root.path] = root } }, self)
end

--- Scan `node`'s directory and (re)populate its children from disk.
--- Stale entries (deleted files) are pruned from the node index.
---@param node Beast.Explorer.Node
function M:expand(node)
  -- stylua: ignore
	if not node.dir or node.expanded then return end

	local found = {} ---@type table<string, boolean>
	local fs = uv.fs_scandir(node.path)

	if not fs then
		return
	end

	while true do
		local name, ftype = uv.fs_scandir_next(fs)
    -- stylua: ignore
		if not name then break end

		ftype = ftype or "unknown"
		found[name] = true
		ensure_child(self, node, name, ftype)
	end

	-- Prune children that no longer exist on disk
	for name, child in pairs(node.children) do
		if not found[name] then
			self.nodes[child] = nil
			node.children[name] = nil
		end
	end

	node.expanded = true
end

-- =============================================================================
-- Navigation: find, open, close, toggle
-- =============================================================================

--- Return the node for `path`, creating ancestor nodes if absent.
---@param path string
---@return Beast.Explorer.Node
function M:find(path)
	path = norm(path)

  -- stylua: ignore
  if self.nodes[path] then return self.nodes[path] end

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
	while node and node.depth >= 0 do
		node.open = true
		node = self.nodes[node.parent]
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

	node.open = false
	node.expanded = false
end

--- Toggle the open state of `path to a folder`.
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

	table.sort(children, function(a, b)
    local node_a = self.nodes[a]
    local node_b = self.nodes[b]
		if node_a.dir ~= node_b.dir then
			return node_a.dir
		end
		return node_a.name:lower() < node_b.name:lower()
	end)

	for i, child_path in ipairs(children) do
    local child = self.nodes[child_path]
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

-- =============================================================================
-- Flat list
-- =============================================================================

---@param opts { show_hidden: boolean, git_status?: table<string, string> }
---@return Beast.Explorer.Node[]
function M:flat(opts)
	local root = self.root

	if not root.expanded then
		self:expand(root)
	end

	if opts.git_status then
		for path, status in pairs(opts.git_status) do
			local node = self.nodes[norm(path)]
			if node then
				node.git_status = status
			end
		end
	end

	local list = {}

	self:walk(root, function(node)
		if node.hidden and not opts.show_hidden then
			return false
		end
		list[#list + 1] = node
	end)

	return list
end

-- =============================================================================
-- Refresh
-- =============================================================================

---@param path string
function M:refresh(path)
	path = norm(path)
	local node = self.nodes[path]
	if not node then
		return
	end

	local function clear(n)
		n.expanded = false
		n.git_status = nil
		for _, child in pairs(n.children) do
			clear(child)
		end
	end

	clear(node)
end

function M:collapse_all()
	for _, node in pairs(self.nodes) do
		if node.dir then
			node.open = false
		end
	end
	self.root.open = true
end

return M
