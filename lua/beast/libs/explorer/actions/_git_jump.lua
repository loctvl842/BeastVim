--- Candidate provider for `next_git_file` / `prev_git_file`: every entry in
--- `state.git.status` except the `ignored` kind (those aren't real changes
--- the user wants to navigate to). Untracked directories appear in the map
--- as a single dir-level record — we stat them so the comparator can place
--- them correctly relative to sibling files.

local jump = require("beast.libs.explorer.actions._jump")
local state = require("beast.libs.explorer.state")

local M = {}

---@param direction "next"|"prev"
function M.jump(direction)
	local status = state.git and state.git.status
	local candidates = {}
	if status then
		for path, st in pairs(status) do
			if st.kind ~= "ignored" then
				candidates[#candidates + 1] = {
					path = path,
					is_dir = vim.fn.isdirectory(path) == 1,
				}
			end
		end
	end
	jump.jump(direction, candidates, "No files with git changes")
end

return M
