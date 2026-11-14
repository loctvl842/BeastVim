--- Result tree of search mode: an explorer `Tree` that lists only the files the
--- finder matched. It never reads the disk (`expand` only prunes), so walk,
--- refresh, watchers and actions cannot bring back files that do not match.
local Tree = require("beast.libs.explorer.tree")

local uv = vim.uv or vim.loop

---@class Beast.Explorer.SearchTree: Beast.Explorer.Tree
---@field positions table<string, table<integer, true>>  path -> 0-based byte offsets of matched letters in the node name
---@field count integer
---@field capped boolean
local M = setmetatable({}, {
	__index = Tree,
	__call = function(t, ...)
		return t:new(...)
	end,
})
M.__index = M

--- Drop children whose path is gone (a delete or rename inside the results);
--- nothing is added.
---@param node Beast.Explorer.Node
function M:expand(node)
	-- stylua: ignore
	if not node.dir or node.expanded then return end

	local changed = false
	for name, child_path in pairs(node.children) do
		if not uv.fs_lstat(child_path) then
			self.nodes[child_path] = nil
			node.children[name] = nil
			changed = true
		end
	end
	node.expanded = true

	if changed then
		self:_touch()
	end
end

--- Create and rename reveal the new file through `open`: let it join the results
--- (the base `open` only adds folders, because it expects `expand` to find files).
---@param path string
function M:open(path)
	if vim.fn.filereadable(path) == 1 then
		self:find(path)
	end
	Tree.open(self, path)
end

--- The real tree watches these directories; leave its watchers alone.
---@param node Beast.Explorer.Node
---@return boolean changed
function M:unwatch_subtree(node)
	local changed = false
	for _, child_path in pairs(node.children) do
		local child = self.nodes[child_path]
		if child and self:unwatch_subtree(child) then
			changed = true
		end
	end
	if node.expanded then
		node.expanded = false
		changed = true
	end
	return changed
end

--- Build the tree for finder `items` (`text` relative to `root`, 1-based `positions` into it).
---@param root string absolute explorer root
---@param items Beast.Finder.Item[]
---@param capped? boolean more matches existed than `items`
---@return Beast.Explorer.SearchTree
function M.from_matches(root, items, capped)
	local self = M:new(root) ---@type Beast.Explorer.SearchTree
	self.positions, self.count, self.capped = {}, #items, capped or false
	self.root.expanded = true

	for _, item in ipairs(items) do
		local node = self.root
		local chain, starts = {}, {} ---@type Beast.Explorer.Node[], integer[]
		local from, rel = 1, item.text
		while from <= #rel + 1 do
			local slash = rel:find("/", from, true)
			local name = rel:sub(from, (slash or #rel + 1) - 1)
			node = self:ensure_child(node, name, slash and "directory" or "file")
			if slash then
				node.open, node.expanded = true, true
			end
			chain[#chain + 1], starts[#starts + 1] = node, from
			-- stylua: ignore
			if not slash then break end
			from = slash + 1
		end

		for _, p in ipairs(item.positions or {}) do
			local seg = #starts
			while starts[seg] > p do
				seg = seg - 1
			end
			-- A matched "/" belongs to no name; only letters inside a name are highlighted.
			local target, off = chain[seg], p - starts[seg]
			if off < #target.name then
				local set = self.positions[target.path] or {}
				set[off], self.positions[target.path] = true, set
			end
		end
	end

	return self
end

return M
