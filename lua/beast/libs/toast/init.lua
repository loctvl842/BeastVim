local Record = require("beast.libs.toast.record")
local State = require("beast.libs.toast.state")
local config = require("beast.libs.toast.config")
local stack = require("beast.libs.toast.stack")

local state = State()

---@class Beast.Toast
---@overload fun(message: string|string[], level?: string|integer, opts?: Beast.Toast.Options): Beast.Toast.Record|{}
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

---@type Beast.Lib.Meta
M.meta = { name = "toast", description = "Transient toast notifications" }

function M.setup(opts)
	config.setup(opts)
	require("beast").apply_highlights("beast.libs.toast.highlights")
end

function M.dismiss()
	stack.dismiss(state)
end

---Re-render an existing sticky toast with updated record fields (message,
---title, icon, etc.). No-op if the toast was already dismissed.
---@param record Beast.Toast.Record
function M.update(record)
	if vim.in_fast_event() then
		vim.schedule(function()
			stack.update(state, record)
		end)
		return
	end
	stack.update(state, record)
end

---Dismiss a single toast by id (the id field of the Record returned by toast()).
---@param id integer
function M.dismiss_id(id)
	if vim.in_fast_event() then
		vim.schedule(function()
			stack.remove(state, id)
		end)
		return
	end
	stack.remove(state, id)
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
