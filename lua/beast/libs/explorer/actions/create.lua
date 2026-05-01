local config = require("beast.libs.explorer.config")
local prompt = require("beast.libs.explorer.prompt")
local state = require("beast.libs.explorer.state")
local ui = require("beast.libs.explorer.ui")

local uv = vim.uv or vim.loop
local M = setmetatable({}, {
	__call = function(t, ...)
		return t.run(...)
	end,
})

---@param target_dir Beast.Explorer.Node
---@param current_node Beast.Explorer.Node
local function show_popup(target_dir, current_node)
	local fresh = state.tree:flat({ show_hidden = config.show_hidden })

	local dir_line = 1 -- below header for root
	if target_dir.depth ~= -1 then
		for i, n in ipairs(fresh) do
			if n.path == target_dir.path then
				break
			end
			dir_line = i + 1 -- +1 for header line
		end
		if not state.anchored then
			dir_line = dir_line + 1
		end
	end

	prompt.inline(target_dir, current_node, function(input)
		local is_dir = input:sub(-1) == "/"
		local rel_path = is_dir and input:sub(1, -2) or input
		local full_path = target_dir.path .. "/" .. rel_path

		if uv.fs_stat(full_path) then
			vim.notify("Already exists: " .. rel_path, vim.log.levels.WARN)
			return false
		end

		return function()
			local parent = is_dir and full_path or vim.fs.dirname(full_path)
			vim.fn.mkdir(parent, "p")

			if not is_dir then
				local fd = uv.fs_open(full_path, "w", 420) -- 0644
				if fd then
					uv.fs_close(fd)
				else
					vim.notify("Failed to create: " .. rel_path, vim.log.levels.ERROR)
					return
				end
			end

			state.tree:refresh(target_dir.path)
			state.tree:open(full_path)
			ui.render(function()
				ui.focus_path(full_path)
			end)
		end
	end)
end

function M.run()
	local node = state.current_node({ show_hidden = config.show_hidden })
  -- stylua: ignore
  if not node then return end

	local target_dir = node.dir and node or state.tree.nodes[node.parent]
  -- stylua: ignore
  if not target_dir then return end

	-- Open closed directory first so children are visible before the popup
	if target_dir.dir and not target_dir.open then
		state.tree:open(target_dir.path)
		ui.render(function()
			show_popup(target_dir, node)
		end)
	else
		show_popup(target_dir, node)
	end
end

return M
