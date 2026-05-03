local util = require("beast.libs.statusline.util")

---@type table<integer, string|false>
local cache = {}
---@type table<integer, true>
local in_flight = {}

---@param bufnr integer
local function fetch(bufnr)
	if in_flight[bufnr] then
		return
	end
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	local name = vim.api.nvim_buf_get_name(bufnr)
	if name == "" then
		cache[bufnr] = false
		return
	end

	in_flight[bufnr] = true
	vim.system(
		{ "git", "log", "-1", "--format=%an (%cr)", "--", name },
		{ text = true },
		vim.schedule_wrap(function(out)
			in_flight[bufnr] = nil
			if not vim.api.nvim_buf_is_valid(bufnr) then
				cache[bufnr] = nil
				return
			end
			if out.code ~= 0 or not out.stdout or out.stdout == "" then
				cache[bufnr] = false
			else
				cache[bufnr] = vim.trim(out.stdout)
			end
			vim.api.nvim_exec_autocmds("User", { pattern = "BeastStatuslineGitChanged" })
		end)
	)
end

local registered = false
local function ensure_autocmds()
	if registered then
		return
	end
	registered = true
	local group = vim.api.nvim_create_augroup("BeastStatuslineGitCommit", { clear = true })
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
		group = group,
		callback = function(args)
			if util.IGNORED_FILETYPES[vim.bo[args.buf].filetype] then
				return
			end
			fetch(args.buf)
		end,
	})
	vim.api.nvim_create_autocmd("BufDelete", {
		group = group,
		callback = function(args)
			cache[args.buf] = nil
			in_flight[args.buf] = nil
		end,
	})
end
ensure_autocmds()

---@type Beast.Statusline.ComponentSpec
return {
	condition = function(ctx)
		return ctx.is_active
	end,
	update = { "User BeastStatuslineGitChanged" },
	scope = "buffer",
	priority = 30,
	provider = function(ctx)
		local v = cache[ctx.bufnr]
		-- stylua: ignore
		if not v then return {} end
		return {
			{ text = " ", hl = { fg = "dimmed3" } },
			{ text = v, hl = { fg = "dimmed3" } },
		}
	end,
}
