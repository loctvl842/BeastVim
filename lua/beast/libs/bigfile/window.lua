-- Window and buffer options a big buffer needs that no single lib owns.
--
-- Fold and conceal settings belong to the window, so they would follow it to
-- the next buffer shown there: the replaced values are kept in `w:beast_bigfile`
-- and put back when the window shows a normal buffer.

local Bigfile = require("beast.libs.bigfile")
local config = require("beast.libs.bigfile.config")

local M = {}

---Window-local values forced for a big buffer, per switched-off feature.
---@type table<string, table<string, any>>
local WIN_OPTS = {
	fold = { foldmethod = "manual" },
	conceal = { conceallevel = 0 },
}

---Window-local scope only: `vim.wo[win][name] = v` behaves like `:set` and would also write the global value.
---@param win integer
---@param name string
---@return any
local function get(win, name)
	return vim.api.nvim_get_option_value(name, { scope = "local", win = win })
end

---@param win integer
---@param name string
---@param value any
local function set(win, name, value)
	vim.api.nvim_set_option_value(name, value, { scope = "local", win = win })
end

---@param win integer
---@param buf integer the buffer `win` now shows
function M.apply(win, buf)
	---@type table<string, any>?
	local saved = vim.w[win].beast_bigfile
	local big = Bigfile.is(buf)
	saved = saved or {}

	for feature, opts in pairs(WIN_OPTS) do
		if config.disable[feature] then
			for name, forced in pairs(opts) do
				local current = get(win, name)
				if big then
					-- Neovim hands a returning buffer its remembered window options before BufWinEnter,
					-- so the current value may already be ours: never record that as the original.
					if saved[name] == nil and current ~= forced then
						saved[name] = current
					end
					set(win, name, forced)
				elseif current == forced then
					-- Still our value: put back what the window had. A split of a big window copies the
					-- forced value but not the record, so fall back to the global default. A different
					-- value was set since (an ftplugin, the user) and is left alone.
					local original = saved[name]
					if original == nil then
						original = vim.go[name]
					end
					set(win, name, original)
				end
			end
		end
	end

	if big then
		vim.w[win].beast_bigfile = saved
		-- Buffer-local, and set here rather than on FileType: an ftplugin may rewrite it after us.
		if config.disable.matchparen then
			vim.bo[buf].matchpairs = ""
		end
	else
		vim.w[win].beast_bigfile = nil
	end
end

return M
