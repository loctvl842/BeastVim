local State = require("beast.libs.notify.state")
local Record = require("beast.libs.notify.record")
local config = require("beast.libs.notify.config")
local stack = require("beast.libs.notify.stack")

local state = State()

local M = setmetatable({}, {
	__call = function(self, m, l, o)
		if vim.in_fast_event() or vim.fn.has("vim_starting") == 1 then
			vim.schedule(function()
				self.notify(m, l, o)
			end)
			return
		end

		return self.notify(m, l, o)
	end,
})

function M.setup(opts)
	config.setup(opts)
	vim.notify = M.notify
  Key.safe_set("n", "<leader>n", M.dismiss, { desc = "Dismiss all notifications", group = "Notify" })
end

function M.dismiss()
	stack.dismiss(state)
end

---@param message string|string[]
---@param level? string|integer
---@param opts? Beast.Notify.Options
function M.notify(message, level, opts)
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
