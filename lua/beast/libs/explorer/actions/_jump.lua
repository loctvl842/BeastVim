--- Shared navigation primitive for cursor jumps in the explorer.
---
--- Given a list of candidate paths (with each candidate's is_dir flag), sorts
--- them in the same top-down DFS order as `tree:walk` (dirs first, then
--- case-insensitive alpha) and moves the cursor to the next/previous one
--- relative to the node under the cursor. Wraps around at the ends.
---
--- Opens closed ancestor folders on the way via `ui.focus_path` so the target
--- row is always visible after the jump.

local config = require("beast.libs.explorer.config")
local state = require("beast.libs.explorer.state")
local ui = require("beast.libs.explorer.ui")

local M = {}

---@param path string
---@param root string
---@return string[]
local function rel_segments(path, root)
	if path == root then
		return {}
	end
	return vim.split(path:sub(#root + 2), "/", { plain = true })
end

--- Compare two paths in tree-walk order. At the first differing segment, a
--- directory beats a file; ties break by lowercase-alpha. A shorter path
--- (ancestor) precedes a longer one (descendant), matching the way `flat`
--- lists a directory line ahead of its children.
---@param a_segs string[]
---@param a_is_dir boolean
---@param b_segs string[]
---@param b_is_dir boolean
---@return boolean
local function path_lt(a_segs, a_is_dir, b_segs, b_is_dir)
	for i = 1, math.min(#a_segs, #b_segs) do
		if a_segs[i] ~= b_segs[i] then
			local a_dir = i < #a_segs or a_is_dir
			local b_dir = i < #b_segs or b_is_dir
			if a_dir ~= b_dir then
				return a_dir
			end
			return a_segs[i]:lower() < b_segs[i]:lower()
		end
	end
	return #a_segs < #b_segs
end

---@class Beast.Explorer.JumpCandidate
---@field path string
---@field is_dir boolean

---@param direction "next"|"prev"
---@param candidates Beast.Explorer.JumpCandidate[]
---@param empty_msg string
function M.jump(direction, candidates, empty_msg)
	-- stylua: ignore
	if not state.tree then return end

	local root = state.tree.root.path
	local prefix = root .. "/"

	local list = {}
	for _, c in ipairs(candidates) do
		if c.path == root or c.path:sub(1, #prefix) == prefix then
			list[#list + 1] = {
				path = c.path,
				is_dir = c.is_dir and true or false,
				segs = rel_segments(c.path, root),
			}
		end
	end

	if #list == 0 then
		vim.notify(empty_msg, vim.log.levels.INFO)
		return
	end

	table.sort(list, function(a, b)
		return path_lt(a.segs, a.is_dir, b.segs, b.is_dir)
	end)

	local cur = state.current_node({ show_hidden = config.show_hidden })
	local cur_segs, cur_is_dir
	if cur then
		cur_segs = rel_segments(cur.path, root)
		cur_is_dir = cur.dir and true or false
	else
		cur_segs, cur_is_dir = {}, true
	end

	local target
	if direction == "next" then
		for _, e in ipairs(list) do
			if path_lt(cur_segs, cur_is_dir, e.segs, e.is_dir) then
				target = e.path
				break
			end
		end
		target = target or list[1].path
	else
		for i = #list, 1, -1 do
			local e = list[i]
			if path_lt(e.segs, e.is_dir, cur_segs, cur_is_dir) then
				target = e.path
				break
			end
		end
		target = target or list[#list].path
	end

	ui.render(function()
		ui.focus_path(target)
	end)
end

return M
