-- Buffer-local review keys. Installed when a session starts, removed (and any
-- pre-existing buffer-local mapping restored) when it ends.

local config = require("beast.libs.review.config")

local M = {}

local ACTIONS = { "accept", "reject", "accept_all", "reject_all", "next", "prev" }

---@class Beast.Review.KeyHandle
---@field lhs string[]
---@field saved table[]  buffer-local maparg dicts that were shadowed

---@param buf integer
---@param handlers table<string, fun()>
---@return Beast.Review.KeyHandle
function M.attach(buf, handlers)
	local handle = { lhs = {}, saved = {} }
	vim.api.nvim_buf_call(buf, function()
		for _, action in ipairs(ACTIONS) do
			local lhs = config.keys[action]
			if lhs and lhs ~= "" then
				local prev = vim.fn.maparg(lhs, "n", false, true)
				if prev.buffer == 1 then
					handle.saved[#handle.saved + 1] = prev
				end
				handle.lhs[#handle.lhs + 1] = lhs
				vim.keymap.set("n", lhs, handlers[action], {
					buffer = buf,
					nowait = true,
					silent = true,
					desc = "Review: " .. action:gsub("_", " "),
				})
			end
		end
	end)
	return handle
end

---@param buf integer
---@param handle Beast.Review.KeyHandle
function M.detach(buf, handle)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	vim.api.nvim_buf_call(buf, function()
		for _, lhs in ipairs(handle.lhs) do
			pcall(vim.keymap.del, "n", lhs, { buffer = buf })
		end
		for _, prev in ipairs(handle.saved) do
			vim.fn.mapset("n", false, prev)
		end
	end)
end

return M
