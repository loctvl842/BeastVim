---@type Beast.Explorer.State
local state = require("beast.libs.explorer.state")
local config = require("beast.libs.explorer.config")
local ui = require("beast.libs.explorer.ui")

local uv = vim.uv or vim.loop

local M = setmetatable({}, {
	__call = function(t, ...)
		return t.run(...)
	end,
})

function M.run()
	if not state.clipboard then
		vim.notify("Clipboard is empty", vim.log.levels.INFO)
		return
	end

	local node = state.current_node({ show_hidden = config.show_hidden })
  -- stylua: ignore
  if not node then return end

	-- Resolve destination directory
	local dest_dir = node.dir and node.path or node.parent or vim.fs.dirname(node.path)

	local mode = state.clipboard.mode
	local paths = state.clipboard.paths

	local pasted = {}
	local errors = {}

	for _, src_path in ipairs(paths) do
		local name = vim.fn.fnamemodify(src_path, ":t")
		local dest_path = dest_dir .. "/" .. name

		if uv.fs_stat(dest_path) then
			table.insert(errors, "Already exists: " .. name)
		elseif mode == "cut" then
			local ok, err = uv.fs_rename(src_path, dest_path)
			if not ok then
				-- Cross-device fallback: cp -r then delete
				vim.fn.system({ "cp", "-r", src_path, dest_path })
				if vim.v.shell_error == 0 then
					vim.fn.delete(src_path, "rf")
					table.insert(pasted, dest_path)
				else
					table.insert(errors, "Move failed: " .. name .. " (" .. (err or "") .. ")")
				end
			end
		else
			-- copy
			vim.fn.system({ "cp", "-r", src_path, dest_path })
			if vim.v.shell_error == 0 then
				table.insert(pasted, dest_path)
			else
				table.insert(errors, "Copy failed: " .. name)
			end
		end
	end
	-- Cut: refresh source parents
	if mode == "cut" then
		for _, src_path in ipairs(paths) do
			state.tree:refresh(vim.fs.dirname(src_path))
		end
	end

	state.clipboard = nil

	-- Notify errors
	for _, err in ipairs(errors) do
		vim.notify(err, vim.log.levels.WARN)
	end

	-- Refresh destination and re-render
	state.tree:refresh(dest_dir)
	if #pasted > 0 then
		ui.focus_path(pasted[1])
	end
	ui.render()
end

return M
