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
local stats = require("beast.libs.finder.engine.stats")

local M = {}

local SHOW_LIMIT = 40

--- Print the recent-query stats ring (prefilter + total timings, survivors).
local function dump_stats()
	local rows = stats.recent()
	if #rows == 0 then
		vim.notify("BeastFinderBigram: no queries recorded (run :BeastFinderBigramDebug enable, then grep)", vim.log.levels.INFO)
		return
	end
	local lines = { string.format("%-20s %8s %5s %8s %6s", "pattern", "prefil", "surv", "total", "hits") }
	for _, r in ipairs(rows) do
		lines[#lines + 1] = string.format(
			"%-20s %6.1fms %5s %6.1fms %6d",
			r.pattern:sub(1, 20),
			r.prefilter_ms,
			r.survivors and tostring(r.survivors) or "full",
			r.total_ms,
			r.results
		)
	end
	vim.api.nvim_echo({ { table.concat(lines, "\n") } }, false, {})
end

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
--- Subcommands: `enable`/`disable` toggle stats; `stats` prints the ring;
--- otherwise args are treated as bigrams/literals to look up candidates.
function M.register()
	if not bigram.available() then
		return
	end
	pcall(vim.api.nvim_create_user_command, "BeastFinderBigramDebug", function(cmd)
		local sub = cmd.fargs[1]
		if sub == "enable" then
			stats.set(true)
			vim.notify("BeastFinderBigram: stats ON — grep, then :BeastFinderBigramDebug stats", vim.log.levels.INFO)
		elseif sub == "disable" then
			stats.set(false)
			vim.notify("BeastFinderBigram: stats OFF", vim.log.levels.INFO)
		elseif sub == "stats" then
			dump_stats()
		elseif #cmd.fargs == 0 then
			vim.notify("usage: :BeastFinderBigramDebug <enable|disable|stats|bigram…>", vim.log.levels.WARN)
		else
			dump(table.concat(cmd.fargs, " "))
		end
	end, {
		nargs = "*",
		complete = function()
			return { "enable", "disable", "stats" }
		end,
		desc = "Bigram prefilter debug: enable/disable/stats or lookup candidates",
	})
end

return M
