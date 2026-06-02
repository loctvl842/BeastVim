-- Async wrapper around `git apply --cached --unidiff-zero`.
--
-- The patch arrives as a list of lines (from patch.lua); we join with "\n"
-- and feed it on stdin, the same protocol mini.diff/gitsigns use. Apply
-- runs out-of-process via `vim.system` so it never blocks the UI thread.

local M = {}

---@param ctx Beast.Git.RepoCtx
---@param patch string[]   Lines to feed on stdin (no trailing newline needed per entry)
---@param reverse boolean  true → invert the patch (used for unstage)
---@param cb fun(ok: boolean, stderr: string)
function M.apply(ctx, patch, reverse, cb)
	local args = { "git", "-C", ctx.toplevel, "apply", "--whitespace=nowarn", "--cached", "--unidiff-zero" }
	if reverse then
		args[#args + 1] = "--reverse"
	end
	args[#args + 1] = "-"

	local stdin = table.concat(patch, "\n") .. "\n"
	vim.system(args, { stdin = stdin, text = true }, function(result)
		vim.schedule(function()
			cb(result.code == 0, result.stderr or "")
		end)
	end)
end

return M
