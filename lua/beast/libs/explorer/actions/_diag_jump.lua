--- Candidate provider for `next_diag_file` / `prev_diag_file`: every file
--- in `state.diagnostics.status` (diagnostics are always file-level).

local jump = require("beast.libs.explorer.actions._jump")
local state = require("beast.libs.explorer.state")

local M = {}

---@param direction "next"|"prev"
function M.jump(direction)
	local status = state.diagnostics and state.diagnostics.status
	local candidates = {}
	if status then
		for path in pairs(status) do
			candidates[#candidates + 1] = { path = path, is_dir = false }
		end
	end
	jump.jump(direction, candidates, "No files with diagnostics")
end

return M
