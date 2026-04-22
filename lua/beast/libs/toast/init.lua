local State = require("beast.libs.toast.state")
local Record = require("beast.libs.toast.record")
local config = require("beast.libs.toast.config")
local stack = require("beast.libs.toast.stack")

local state = State()

local M = setmetatable({}, {
	__call = function(self, m, l, o)
		if vim.in_fast_event() or vim.fn.has("vim_starting") == 1 then
			vim.schedule(function()
				self.toast(m, l, o)
			end)
			return
		end

		return self.toast(m, l, o)
	end,
})

function M.setup(opts)
	config.setup(opts)
end

function M.dismiss()
	stack.dismiss(state)
end

---@param message string|string[]
---@param level? string|integer
---@param opts? Beast.Toast.Options
---@return Beast.Toast.Record|{}
function M.toast(message, level, opts)
	local level_num = vim.log.levels[config.normalize_level(level or "INFO")]
	if level_num < config.level then
		return {}
	end

	local record = Record(state.next_id, message, level, opts)
	state.next_id = state.next_id + 1

	stack.push(state, record)
	return record
end

return M
