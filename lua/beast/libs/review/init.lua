local config = require("beast.libs.review.config")
local session = require("beast.libs.review.session")

local M = {}

---@type Beast.Lib.Meta
M.meta = { name = "review", description = "Review proposed file changes inline, hunk by hunk." }

--- Propose `contents` as the new text of `path`. The file opens in a window
--- (or is created), the change shows as Current vs Incoming hunks, and
--- `on_done` fires once every hunk is decided. Nothing is written until at
--- least one hunk is accepted.
---@param path string
---@param contents string
---@param on_done? fun(outcome: Beast.Review.Outcome, stats: Beast.Review.Stats)
function M.propose(path, contents, on_done)
	local buf = vim.fn.bufadd(vim.fn.fnamemodify(path, ":p"))
	vim.fn.bufload(buf)
	vim.bo[buf].buflisted = true
	session.submit(buf, contents, on_done or function() end)
end

---@param opts? Beast.Review.Config
function M.setup(opts)
	require("beast").apply_highlights("beast.libs.review.highlights")
	config.setup(opts)

	-- Manual driver: treat a local file as the proposal for the current buffer.
	vim.api.nvim_create_user_command("Review", function(o)
		local sub, arg = o.fargs[1], o.fargs[2]
		if sub ~= "propose" or not arg then
			vim.notify("usage: :Review propose <file with proposed contents>", vim.log.levels.ERROR, { title = M.meta.name })
			return
		end
		local f, err = io.open(vim.fn.expand(arg), "rb")
		if not f then
			vim.notify(err, vim.log.levels.ERROR, { title = M.meta.name })
			return
		end
		local text = f:read("*a")
		f:close()
		M.propose(vim.api.nvim_buf_get_name(0), text)
	end, { nargs = "+", complete = "file", desc = "Review proposed file contents" })
end

return M
