---@class Beast.Packer.Operation.Status
---@field status "pending"|"in_progress"|"success"|"error"
---@field kind "install"|"update"|"load"
---@field message string|nil
---@field start_time integer      -- os.time() when started
---@field start_time_hr integer   -- hrtime() for precise elapsed
---@field elapsed_ms number|nil   -- Calculated elapsed time in ms

local M = {}

M.status = {} ---@type table<string, Beast.Packer.Operation.Status>

---@param plugin_name string
---@param kind "install"|"update"|"load"
function M.start(plugin_name, kind)
	M.status[plugin_name] = {
		status = "in_progress",
		kind = kind,
		message = nil,
		start_time = os.time(),
		start_time_hr = Util.hrtime(),
		elapsed_ms = nil,
	}
end

---@private
---@return boolean
function M.any_in_progress()
	for _, op in pairs(M.status) do
		if op.status == "in_progress" or op.status == "pending" then
			return true
		end
	end
	return false
end

---@param plugin_name string
---@param success boolean
---@param message? string
function M.complete(plugin_name, success, message)
	local op = M.status[plugin_name]
  -- stylua: ignore
	if not op then return end

	local elapsed_ns = Util.hrtime() - op.start_time_hr
	op.elapsed_ms = elapsed_ns / 1e6 -- Convert to milliseconds
	op.status = success and "success" or "error"
	op.message = message
end

function M.clear_completed()
	for plugin_name, op in pairs(M.status) do
		if op.status == "success" or op.status == "error" then
			M.status[plugin_name] = nil
		end
	end
end

return M
