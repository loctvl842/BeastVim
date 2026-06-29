-- :BeastFinderBigramDebug — inspect the live_grep bigram prefilter.
--
-- Usage:
--   :BeastFinderBigramDebug ca le   → files whose bitset has BOTH 'ca' and 'le'
--   :BeastFinderBigramDebug error   → candidate files for the literal "error"
-- Prints a header (count + index stats) then up to a cap of candidate paths.
-- If no index is built for the cwd yet, it builds one on demand, then reruns.

local bigram = require("beast.libs.finder.engine.bigram")
local config = require("beast.libs.finder.config")
local index = require("beast.libs.finder.engine.index")

local M = {}

local SHOW_LIMIT = 40

--- Print candidates for the space-joined query against the cwd index.
---@param query string
local function dump(query)
	local cwd = vim.fn.getcwd()
	local idx = index.get(cwd)
	if not idx then
		vim.notify("BeastFinderBigram: building index for " .. cwd .. "…", vim.log.levels.INFO)
		index.build(cwd, {
			max_files = config.engine.max_files,
			max_file_size = config.engine.max_file_size,
		}, function()
			dump(query)
		end)
		return
	end

	local files = idx:query(query) or {}
	local s = idx.bigram:stats()
	local lines = {
		string.format("'%s' → %d candidate files  (index: %d files, %d cols)", query, #files, s.files, s.columns),
	}
	for i = 1, math.min(SHOW_LIMIT, #files) do
		lines[#lines + 1] = "  " .. files[i]
	end
	if #files > SHOW_LIMIT then
		lines[#lines + 1] = string.format("  … and %d more", #files - SHOW_LIMIT)
	end
	vim.api.nvim_echo({ { table.concat(lines, "\n") } }, false, {})
end

--- Register :BeastFinderBigramDebug (idempotent).
function M.register()
	if not bigram.available() then
		return
	end
	pcall(vim.api.nvim_create_user_command, "BeastFinderBigramDebug", function(cmd)
		if #cmd.fargs == 0 then
			vim.notify("usage: :BeastFinderBigramDebug <bigram|literal> …", vim.log.levels.WARN)
			return
		end
		dump(table.concat(cmd.fargs, " "))
	end, { nargs = "+", desc = "Show bigram prefilter candidate files (AND of args)" })
end

return M
