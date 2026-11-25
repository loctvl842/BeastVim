-- Big file detection: one question, "is this buffer big, and is feature X off
-- for it?". Libs ask `disabled(buf, feature)` at their own exclusion point.
--
-- The answer is computed on first ask and kept per buffer until it unloads, so
-- callers need no autocmd ordering (treesitter's FileType handler may run
-- before ours). A buffer that is not loaded yet is never decided: its line
-- count is a placeholder and would make a small file look minified.

local config = require("beast.libs.bigfile.config")

local api = vim.api

---@class Beast.Bigfile
local M = {}

---@type Beast.Lib.Meta
M.meta = { name = "bigfile", description = "Switch off costly features for very large files" }

---Verdict per buffer; absent until decided.
---@type table<integer, boolean>
local memo = {}

---Buffers already announced, so FileType + BufReadPost + `:e` toast once per open.
---@type table<integer, true>
local notified = {}

---@param buf? integer
---@return integer
local function resolve(buf)
	return (buf == nil or buf == 0) and api.nvim_get_current_buf() or buf
end

---Big when the file is over `size` bytes, or its lines are so long on average
---that it looks minified.
---@param buf integer
---@return boolean?
local function classify(buf)
	local size = vim.fn.getfsize(api.nvim_buf_get_name(buf))
	if size <= 0 then
		return false
	end
	if size > config.size then
		return true
	end
	local lines = api.nvim_buf_line_count(buf)
	-- At BufReadPre the buffer is loaded but still holds one empty line, which would make any file
	-- look minified: wait until it has been read.
	if size > 1 and api.nvim_buf_get_offset(buf, lines) <= 1 then
		return nil
	end
	return (size - lines) / lines > config.line_length
end

---@param buf? integer defaults to the current buffer
---@return boolean
function M.is(buf)
	buf = resolve(buf)
	local hit = memo[buf]
	if hit ~= nil then
		return hit
	end
	-- stylua: ignore
	if not config.enabled or not api.nvim_buf_is_valid(buf) or not api.nvim_buf_is_loaded(buf) then return false end
	-- stylua: ignore
	if vim.bo[buf].buftype ~= "" or api.nvim_buf_get_name(buf) == "" then return false end
	hit = classify(buf)
	-- stylua: ignore
	if hit == nil then return false end
	memo[buf] = hit
	return hit
end

---Is `feature` switched off for `buf`? False for every normal buffer.
---@param buf? integer defaults to the current buffer
---@param feature string key of `Beast.Bigfile.Disable`
---@return boolean
function M.disabled(buf, feature)
	return config.disable[feature] == true and M.is(buf)
end

---Decimal units, as `ls` and the Finder report them.
---@param bytes integer
---@return string
local function human(bytes)
	if bytes >= 1e6 then
		return ("%.1f MB"):format(bytes / 1e6)
	end
	return ("%d KB"):format(math.max(1, math.floor(bytes / 1e3 + 0.5)))
end

---@param buf integer
local function announce(buf)
	-- stylua: ignore
	if not config.notify or notified[buf] or not M.is(buf) then return end
	notified[buf] = true
	local name = api.nvim_buf_get_name(buf)
	Toast(
		("%s (%s) is large. Some features are disabled."):format(vim.fn.fnamemodify(name, ":~:."), human(vim.fn.getfsize(name))),
		vim.log.levels.WARN,
		{ title = "Big File" }
	)
end

---@param opts? Beast.Bigfile.Config
function M.setup(opts)
	config.setup(opts)
	memo, notified = {}, {}

	local group = api.nvim_create_augroup("BeastBigfile", { clear = true })

	-- A file with no detected filetype never fires FileType, so BufReadPost covers it too.
	api.nvim_create_autocmd({ "FileType", "BufReadPost" }, {
		group = group,
		callback = function(ev)
			announce(ev.buf)
		end,
	})

	-- Fold, conceal and matchparen follow the window or buffer, so they are set as it is shown.
	api.nvim_create_autocmd("BufWinEnter", {
		group = group,
		callback = function(ev)
			require("beast.libs.bigfile.window").apply(api.nvim_get_current_win(), ev.buf)
		end,
	})

	-- `:e` unloads and reloads the buffer, so the verdict is recomputed (the file may have changed)...
	api.nvim_create_autocmd("BufUnload", {
		group = group,
		callback = function(ev)
			memo[ev.buf] = nil
		end,
	})

	-- ...but the toast is only repeated once the buffer is really gone.
	api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
		group = group,
		callback = function(ev)
			memo[ev.buf], notified[ev.buf] = nil, nil
		end,
	})
end

return M
