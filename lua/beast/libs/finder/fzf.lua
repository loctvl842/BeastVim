--- fzf terminal lifecycle: spawn, parse output, cleanup.
--- Embeds fzf in a Neovim terminal buffer for native filtering performance.
local M = {}

--- Generate a unique temp file path
---@return string
local function tempname()
	return vim.fn.tempname()
end

---@class Beast.Finder.Fzf.Opts
---@field cwd? string working directory for fzf
---@field fzf_args? string[] extra fzf CLI args
---@field prompt? string fzf prompt string
---@field header? string fzf header text

---@class Beast.Finder.Fzf.Result
---@field action string the key pressed ("enter", "ctrl-s", "ctrl-v", "ctrl-t") or empty on abort
---@field lines string[] selected line(s)

--- Run fzf in a terminal buffer.
--- The current window+buffer must be the target for the terminal.
---@param cmd string shell command that produces input lines (FZF_DEFAULT_COMMAND)
---@param opts Beast.Finder.Fzf.Opts
---@param on_done fun(result: Beast.Finder.Fzf.Result|nil) nil = aborted/error
---@return integer job_id
---@return string focus_file path to the focus temp file (for preview polling)
function M.run(cmd, opts, on_done)
	opts = opts or {}
	local output_file = tempname()
	local focus_file = tempname()

	-- Build fzf CLI
	local fzf_args = {
		"--layout=reverse",
		"--border=none",
		"--no-separator",
		"--no-scrollbar",
		"--ansi",
		"--expect=ctrl-s,ctrl-v,ctrl-t",
		"--bind=focus:execute-silent(echo {} > " .. vim.fn.shellescape(focus_file) .. ")",
	}

	if opts.prompt then
		fzf_args[#fzf_args + 1] = "--prompt=" .. opts.prompt
	else
		fzf_args[#fzf_args + 1] = "--prompt=  "
	end

	if opts.header then
		fzf_args[#fzf_args + 1] = "--header=" .. opts.header
	end

	-- User extra args
	if opts.fzf_args then
		for _, arg in ipairs(opts.fzf_args) do
			fzf_args[#fzf_args + 1] = arg
		end
	end

	-- Output redirection
	local fzf_cmd = table.concat(fzf_args, " ") .. " > " .. vim.fn.shellescape(output_file)

	-- Full shell command: pipe source output directly into fzf
	-- This avoids FZF_DEFAULT_COMMAND escaping complexities
	-- Unset FZF_DEFAULT_OPTS to prevent user's global config from interfering
	local shell_cmd
	if opts.cwd then
		shell_cmd = string.format("cd %s && FZF_DEFAULT_OPTS='' %s | fzf %s", vim.fn.shellescape(opts.cwd), cmd, fzf_cmd)
	else
		shell_cmd = string.format("FZF_DEFAULT_OPTS='' %s | fzf %s", cmd, fzf_cmd)
	end

	-- Use termopen which works in the current buffer
	local job_id = vim.fn.termopen(shell_cmd, {
		on_exit = function(_, rc, _)
			vim.schedule(function()
				-- Parse output file
				local result = nil
				if rc == 0 then
					local f = io.open(output_file)
					if f then
						local content = f:read("*a")
						f:close()
						if content and content ~= "" then
							local lines = vim.split(content, "\n", { trimempty = true })
							if #lines >= 1 then
								local action_key = lines[1]
								local selected = {}
								for i = 2, #lines do
									if lines[i] ~= "" then
										selected[#selected + 1] = lines[i]
									end
								end
								result = {
									action = action_key ~= "" and action_key or "enter",
									lines = selected,
								}
							end
						end
					end
				end
				-- rc=130 or rc=1: user aborted or no match → result stays nil

				-- Cleanup temp files
				pcall(vim.fn.delete, output_file)

				on_done(result)
			end)
		end,
	})

	-- Enter terminal insert mode so user can type immediately
	vim.cmd("startinsert")

	return job_id, focus_file
end

return M
