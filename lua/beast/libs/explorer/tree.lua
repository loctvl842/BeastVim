--- Pure tree data model — no windows, no rendering, no side-effects.
--- The caller (init.lua) owns the Beast.Explorer.Tree instance and passes it in.
---
--- Dependency chain:  tree.lua → git.lua (only used by Tree.flat)
--- tree.lua does NOT require config — config concerns belong to win.lua / init.lua.

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
---@field children  table<string, Beast.Explorer.Node>
---@field parent?   Beast.Explorer.Node

---@class Beast.Explorer.Tree
---@field root  Beast.Explorer.Node     virtual root (path = "")
---@field nodes table<string, Beast.Explorer.Node>  path → node index

local Tree = {}
Tree.__index = Tree

local uv = vim.uv or vim.loop

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Normalise a path: absolute, no trailing slash.
---@param p string
---@return string
local function norm(p)
	return (vim.fn.fnamemodify(p, ":p"):gsub("/$", ""))
end

--- Return-or-create the child of `parent` identified by `name` / `ftype`.
---@param tree   Beast.Explorer.Tree
---@param parent Beast.Explorer.Node
---@param name   string
---@param ftype  string
---@return Beast.Explorer.Node
local function ensure_child(tree, parent, name, ftype)
    -- stylua: ignore
    if parent.children[name] then return parent.children[name] end

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
		parent = parent,
	}
	parent.children[name] = node
	tree.nodes[path] = node
	return node
end

-- ---------------------------------------------------------------------------
-- Constructor
-- ---------------------------------------------------------------------------

--- Create a new, empty tree.
---@return Beast.Explorer.Tree
function Tree.new(cwd)
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
	return setmetatable({ root = root, nodes = { [cwd] = root } }, Tree)
end

-- ---------------------------------------------------------------------------
-- Disk operations
-- ---------------------------------------------------------------------------

--- Scan `node`'s directory and (re)populate its children from disk.
--- Stale entries (deleted files) are pruned from the node index.
---@param tree Beast.Explorer.Tree
---@param node Beast.Explorer.Node
function Tree.expand(tree, node)
    -- stylua: ignore
    if not node.dir   then return end
    -- stylua: ignore
    if node.expanded  then return end

	local found = {} ---@type table<string, boolean>
	local fs = uv.fs_scandir(node.path)
	while fs do
		local name, t = uv.fs_scandir_next(fs)
        -- stylua: ignore
        if not name then break end
		t = t or "unknown"
		found[name] = true
		local child = ensure_child(tree, node, name, t)
		child.type = t
		child.dir = t == "directory" or (t == "link" and vim.fn.isdirectory(child.path) == 1)
	end

	-- Prune children that no longer exist on disk
	for name, child in pairs(node.children) do
		if not found[name] then
			tree.nodes[child.path] = nil
			node.children[name] = nil
		end
	end

	node.expanded = true
end

-- ---------------------------------------------------------------------------
-- Navigation: find / open / close / toggle
-- ---------------------------------------------------------------------------

--- Return the node for `path`, creating ancestor nodes if absent.
---@param tree Beast.Explorer.Tree
---@param path string
---@return Beast.Explorer.Node
function Tree.find(tree, path)
	path = norm(path)
    -- stylua: ignore
    if tree.nodes[path] then return tree.nodes[path] end

	local root_path = tree.root.path
	-- path must live inside the tree root
	if path:sub(1, #root_path + 1) ~= (root_path .. "/") then
		return nil
	end

	-- walk only the relative portion: "lua/beast/init.lua"
	local rel = path:sub(#root_path + 2)
	local parts = vim.split(rel, "/", { plain = true })
	local node = tree.root
	for i, part in ipairs(parts) do
		local cur = root_path .. "/" .. table.concat(parts, "/", 1, i)
		local ftype = vim.fn.isdirectory(cur) == 1 and "directory" or "file"
		node = ensure_child(tree, node, part, ftype)
	end
	return node
end

--- Mark `path` (and all its ancestors up to root) as open.
---@param tree Beast.Explorer.Tree
---@param path string
function Tree.open(tree, path)
    -- stylua: ignore
    if vim.fn.isdirectory(path) ~= 1 then path = vim.fs.dirname(path) end
	local node = Tree.find(tree, path)
	while node and node.depth >= 0 do -- ← was node.path ~= ""
		node.open = true
		node = node.parent
	end
end

--- Collapse the directory at `path`.
---@param tree Beast.Explorer.Tree
---@param path string
function Tree.close(tree, path)
    -- stylua: ignore
    if vim.fn.isdirectory(path) ~= 1 then path = vim.fs.dirname(path) end
	local node = Tree.find(tree, path)
    -- stylua: ignore
    if not node then return end
	node.open = false
	node.expanded = false -- force rescan next time it is opened
end

--- Toggle the directory at `path` between open and closed.
---@param tree Beast.Explorer.Tree
---@param path string
function Tree.toggle(tree, path)
    -- stylua: ignore
    if vim.fn.isdirectory(path) ~= 1 then path = vim.fs.dirname(path) end
	local node = Tree.find(tree, path)
    -- stylua: ignore
    if not node then return end
	if node.open then
		Tree.close(tree, path)
	else
		Tree.open(tree, path)
	end
end

-- ---------------------------------------------------------------------------
-- Traversal
-- ---------------------------------------------------------------------------

--- Walk visible nodes under `node` in depth-first order.
--- `fn(node)` may return `false` to skip a directory's children.
---@param tree Beast.Explorer.Tree
---@param node Beast.Explorer.Node
---@param fn   fun(node: Beast.Explorer.Node): boolean?
function Tree.walk(tree, node, fn)
	-- Sort: directories first, then alphabetically (case-insensitive)
	local children = vim.tbl_values(node.children) ---@type Beast.Explorer.Node[]
	table.sort(children, function(a, b)
		if a.dir ~= b.dir then
			return a.dir
		end
		return a.name:lower() < b.name:lower()
	end)

	for i, child in ipairs(children) do
		child.last = (i == #children)
		local descend = fn(child)
		if descend ~= false and child.dir and child.open then
			if not child.expanded then
				Tree.expand(tree, child)
			end
			Tree.walk(tree, child, fn)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Flat list (for rendering)
-- ---------------------------------------------------------------------------

--- Build an ordered, flat list of visible nodes under `cwd`.
--- Applies show_hidden filter and overlays git_status onto matching nodes.
---
---@param tree Beast.Explorer.Tree
---@param cwd  string
---@param opts { show_hidden: boolean, git_status?: table<string, string> }
---@return Beast.Explorer.Node[]
function Tree.flat(tree, opts)
	local root = tree.root -- always correct now
	if not root.expanded then
		Tree.expand(tree, root)
	end
	-- git overlay (unchanged) ...
	local list = {}
	Tree.walk(tree, root, function(node)
		if node.hidden and not opts.show_hidden then
			return false
		end
		list[#list + 1] = node
	end)
	return list
end

-- ---------------------------------------------------------------------------
-- Refresh (invalidate subtree so next expand() re-reads disk)
-- ---------------------------------------------------------------------------

--- Mark the subtree at `path` as unexpanded so the next flat() rescans disk.
---@param tree Beast.Explorer.Tree
---@param path string
function Tree.refresh(tree, path)
	path = norm(path)
	local node = tree.nodes[path]
    -- stylua: ignore
    if not node then return end

	local function clear(n)
		n.expanded = false
		n.git_status = nil
		for _, child in pairs(n.children) do
			clear(child)
		end
	end
	clear(node)
end

--- Collapse every directory in the tree, leaving only root open.
--- Call this before reveal() so only the target file's ancestors are re-opened.
---@param tree Beast.Explorer.Tree
function Tree.collapse_all(tree)
	for _, node in pairs(tree.nodes) do
        -- stylua: ignore
        if node.dir then node.open = false end
	end
	tree.root.open = true -- root must stay open
end

return Tree
