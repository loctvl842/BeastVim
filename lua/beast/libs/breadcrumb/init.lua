local config = require("beast.libs.breadcrumb.config")
local context = require("beast.libs.breadcrumb.context")
local filepath = require("beast.libs.breadcrumb.filepath")

local M = {}

-- =========================================================================
-- State (only this file mutates it)
-- =========================================================================

---@class Beast.Breadcrumb.State
---@field cache table<integer, Beast.Breadcrumb.CacheEntry>  Per-window cache keyed by winid
---@field augroup? integer

---@class Beast.Breadcrumb.CacheEntry
---@field bufnr integer
---@field modified boolean
---@field output string

---@type Beast.Breadcrumb.State
local state = {
	cache = {},
	augroup = nil,
}

-- =========================================================================
-- Cache invalidation
-- =========================================================================

---Invalidate cache for a specific window.
---@param winid integer
local function invalidate_win(winid)
	state.cache[winid] = nil
end

---Invalidate all cache entries that reference a given buffer.
---@param bufnr integer
local function invalidate_buf(bufnr)
	for winid, entry in pairs(state.cache) do
		if entry.bufnr == bufnr then
			state.cache[winid] = nil
		end
	end
end

-- =========================================================================
-- Autocmd registration (lazy, idempotent)
-- =========================================================================

local WINBAR_EXPR = "%!v:lua.require'beast.libs.breadcrumb'.render()"

---Check if a buffer should be ignored for winbar display.
---@param buf integer
---@return boolean
local function is_ignored(buf)
	local ft = vim.bo[buf].filetype
	local bt = vim.bo[buf].buftype
	return config.ignored_filetypes[ft] or config.ignored_buftypes[bt] or false
end

local function ensure_autocmds()
	-- stylua: ignore
	if state.augroup then return end

	state.augroup = vim.api.nvim_create_augroup("BeastBreadcrumb", { clear = true })

	-- Buffer enter: set/remove winbar per-window and invalidate cache
	vim.api.nvim_create_autocmd("BufEnter", {
		group = state.augroup,
		callback = function()
			local winid = vim.api.nvim_get_current_win()
			local buf = vim.api.nvim_win_get_buf(winid)
			if is_ignored(buf) then
				vim.wo[winid].winbar = nil
			else
				vim.wo[winid].winbar = WINBAR_EXPR
			end
			invalidate_win(winid)
			vim.schedule(function()
				vim.cmd("redrawstatus")
			end)
		end,
	})

	-- Modified state change: invalidate all windows showing this buffer
	vim.api.nvim_create_autocmd({ "BufModifiedSet", "BufWritePost" }, {
		group = state.augroup,
		callback = function(args)
			invalidate_buf(args.buf)
			vim.schedule(function()
				vim.cmd("redrawstatus")
			end)
		end,
	})

	-- Clean up cache for closed windows; invalidate all on resize
	vim.api.nvim_create_autocmd("WinClosed", {
		group = state.augroup,
		callback = function(args)
			local winid = tonumber(args.match)
			if winid then
				state.cache[winid] = nil
			end
		end,
	})

	vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
		group = state.augroup,
		callback = function()
			state.cache = {}
			vim.schedule(function()
				vim.cmd("redrawstatus")
			end)
		end,
	})
end

-- =========================================================================
-- Public API
-- =========================================================================

---Render the winbar. Called by Neovim via %!v:lua.require'beast.libs.breadcrumb'.render()
---@return string
function M.render()
	local ctx = context.build()

	-- Early return for ignored filetypes/buftypes
	-- stylua: ignore
	if config.ignored_filetypes[ctx.filetype] then return "" end
	-- stylua: ignore
	if config.ignored_buftypes[ctx.buftype] then return "" end

	-- Cache check: hit if same buffer and same modified state
	local cached = state.cache[ctx.winid]
	local modified = vim.bo[ctx.bufnr].modified
	if cached and cached.bufnr == ctx.bufnr and cached.modified == modified then
		return cached.output
	end

	-- Cache miss: render filepath
	local output = " " .. filepath.render(ctx, config.separator, config.modified_icon)

	-- Store in cache
	state.cache[ctx.winid] = {
		bufnr = ctx.bufnr,
		modified = modified,
		output = output,
	}

	return output
end

---Setup the breadcrumb library. Idempotent — safe to call multiple times.
---@param opts? Beast.Breadcrumb.Config
function M.setup(opts)
	config.setup(opts)
	require("beast.libs.breadcrumb.highlights")

	-- Reset cache on re-setup
	state.cache = {}
	state.augroup = nil

	ensure_autocmds()

	-- Set winbar per-window (not globally) so ignored windows stay clean
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		if not is_ignored(buf) then
			vim.wo[win].winbar = WINBAR_EXPR
		end
	end
end

---Mark cache as dirty for all windows (for benchmarking and external invalidation).
function M._invalidate()
	state.cache = {}
end

return M
