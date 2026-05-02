local util = require("beast.libs.statusline.util")

---@param bufnr integer
---@return string?
local function last_commit_for_buf(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr)
	-- stylua: ignore
	if name == "" then return nil end
	local result = vim.fn.system({ "git", "log", "-1", "--format=%an (%cr)", "--", name })
	if vim.v.shell_error ~= 0 or not result or result == "" then
		return nil
	end
	return vim.trim(result)
end

local get_commit = util.file_bound(function(ctx)
	return last_commit_for_buf(ctx.bufnr) or false
end)

---@type Beast.Statusline.ComponentSpec
return {
	condition = function(ctx)
		return ctx.is_active
	end,
	update = { "BufEnter", "BufWritePost", "User BeastStatuslineGitChanged" },
	scope = "buffer",
	priority = 30,
	provider = function(ctx)
		local result = get_commit(ctx)
		-- stylua: ignore
		if not result then return {} end
		return {
			{ text = " ", hl = { fg = "dimmed3" } },
			{ text = result, hl = { fg = "dimmed3" } },
		}
	end,
}
