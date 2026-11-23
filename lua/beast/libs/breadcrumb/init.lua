local config = require("beast.libs.breadcrumb.config")
local context = require("beast.libs.breadcrumb.context")
local filepath = require("beast.libs.breadcrumb.filepath")
local symbols = require("beast.libs.breadcrumb.symbols")

local M = {}

---@type Beast.Lib.Meta
M.meta = { name = "breadcrumb", description = "Winbar breadcrumb showing file path and code context" }

-- =========================================================================
-- State (only this file mutates it)
-- =========================================================================

---@class Beast.Breadcrumb.State
---@field cache table<integer, Beast.Breadcrumb.CacheEntry>  Per-window cache keyed by winid
---@field augroup? integer
---@field dirty_wins table<integer, true>  Windows whose cursor moved since the last flush
---@field dirty_bufs table<integer, true>  Buffers whose symbols should be re-requested

---@class Beast.Breadcrumb.CacheEntry
---@field bufnr integer
---@field bufname string
---@field modified boolean
---@field output string

---@type Beast.Breadcrumb.State
local state = {
	cache = {},
	augroup = nil,
	dirty_wins = {},
	dirty_bufs = {},
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
-- Debounce
-- =========================================================================

-- A cursor that keeps moving (holding `j`) never settles, so nothing is recomputed
-- until it stops. Symbol refreshes wait longer: one request per typing pause, not per key.
local CURSOR_SETTLE_MS = 60
local REFRESH_SETTLE_MS = 300

---@param ms integer
---@param fn fun()
---@return fun() schedule  (Re)start the countdown
---@return fun() stop
local function debounce(ms, fn)
	local timer = assert(vim.uv.new_timer())
	local run = vim.schedule_wrap(fn)
	return function()
		timer:start(ms, 0, run)
	end, function()
		timer:stop()
	end
end

local schedule_cursor, stop_cursor = debounce(CURSOR_SETTLE_MS, function()
	local wins = state.dirty_wins
	state.dirty_wins = {}
	for winid in pairs(wins) do
		invalidate_win(winid)
	end
	vim.cmd("redrawstatus")
end)

local schedule_refresh, stop_refresh = debounce(REFRESH_SETTLE_MS, function()
	local bufs = state.dirty_bufs
	state.dirty_bufs = {}
	for bufnr in pairs(bufs) do
		-- The syntax tree has no push signal: a typing pause is when its trail may have changed
		invalidate_buf(bufnr)
		symbols.refresh(bufnr)
	end
	vim.cmd("redrawstatus")
end)

---@param bufnr integer
local function request_refresh(bufnr)
	state.dirty_bufs[bufnr] = true
	schedule_refresh()
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
			if config.symbols and not is_ignored(buf) then
				request_refresh(buf)
			end
			vim.schedule(function()
				vim.cmd("redrawstatus")
			end)
		end,
	})

	-- Modified / rename / delete: invalidate windows showing this buffer
	vim.api.nvim_create_autocmd({ "BufModifiedSet", "BufWritePost", "BufFilePost", "BufDelete" }, {
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

	-- stylua: ignore
	if not config.symbols then return end

	-- Symbols arrived or changed: redraw the windows showing that buffer
	symbols.on_change(function(bufnr)
		invalidate_buf(bufnr)
		vim.schedule(function()
			vim.cmd("redrawstatus")
		end)
	end)

	-- Cursor moved: recompute that window's trail once the cursor settles
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
		group = state.augroup,
		callback = function()
			state.dirty_wins[vim.api.nvim_get_current_win()] = true
			schedule_cursor()
		end,
	})

	vim.api.nvim_create_autocmd("LspAttach", {
		group = state.augroup,
		callback = function(args)
			request_refresh(args.buf)
		end,
	})

	-- The detaching client is still listed while the event runs; look after it is gone
	vim.api.nvim_create_autocmd("LspDetach", {
		group = state.augroup,
		callback = function(args)
			vim.schedule(function()
				symbols.clear(args.buf)
				invalidate_buf(args.buf)
				request_refresh(args.buf)
			end)
		end,
	})

	-- Slow servers answer with nothing until indexing is done; ask again when work ends
	vim.api.nvim_create_autocmd("LspProgress", {
		group = state.augroup,
		callback = function(args)
			local value = args.data and args.data.params and args.data.params.value
			if not (value and value.kind == "end") then
				return
			end
			local client = vim.lsp.get_client_by_id(args.data.client_id)
			for bufnr in pairs(client and client.attached_buffers or {}) do
				request_refresh(bufnr)
			end
		end,
	})

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave", "FileType" }, {
		group = state.augroup,
		callback = function(args)
			request_refresh(args.buf)
		end,
	})

	vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
		group = state.augroup,
		callback = function(args)
			symbols.clear(args.buf)
			state.dirty_bufs[args.buf] = nil
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

	-- Cache check: hit if same buffer, name, and modified state
	local cached = state.cache[ctx.winid]
	local modified = vim.bo[ctx.bufnr].modified
	if cached and cached.bufnr == ctx.bufnr and cached.bufname == ctx.bufname and cached.modified == modified then
		return cached.output
	end

	-- Cache miss: render filepath + symbol trail
	local trail = config.symbols and symbols.trail(ctx.bufnr, ctx.winid) or nil
	local output = " " .. filepath.render(ctx, config.separator, config.modified_icon, trail)

	-- Store in cache
	state.cache[ctx.winid] = {
		bufnr = ctx.bufnr,
		bufname = ctx.bufname,
		modified = modified,
		output = output,
	}

	return output
end

---Setup the breadcrumb library. Idempotent — safe to call multiple times.
---@param opts? Beast.Breadcrumb.Config
function M.setup(opts)
	config.setup(opts)
	require("beast").apply_highlights("beast.libs.breadcrumb.highlights")

	-- Reset cache and pending work on re-setup
	state.cache = {}
	state.augroup = nil
	state.dirty_wins = {}
	state.dirty_bufs = {}
	stop_cursor()
	stop_refresh()

	ensure_autocmds()

	-- Set winbar per-window (not globally) so ignored windows stay clean
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		if not is_ignored(buf) then
			vim.wo[win].winbar = WINBAR_EXPR
			-- Servers attached before this lib loaded never fired our LspAttach
			if config.symbols then
				request_refresh(buf)
			end
		end
	end
end

---Mark cache as dirty for all windows (for benchmarking and external invalidation).
function M._invalidate()
	state.cache = {}
end

return M
