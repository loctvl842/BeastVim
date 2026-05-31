-- FFI surface for statuscolumn.
--
-- Two consumers:
--   * `display_tick` — global counter Neovim bumps on every redraw. Used as
--     the per-window cache invalidation key (statuscol.nvim approach).
--   * `fold_info(win, lnum)` — returns fold start/level/lines for the line.
--     Used by the fold producer in Phase 3.
--
-- All access is pcall-guarded. On non-LuaJIT or ABI drift, the lib degrades:
-- tick stays at 0 (cache never invalidates on tick alone — only on
-- WinClosed/explicit invalidation), and fold_info returns nil.

local M = {}

---@type ffi.namespace*?
local C = nil
local loaded = false
local symbols = { display_tick = false, fold_info = false, find_window_by_handle = false }

local function load_ffi()
	if loaded then
		return
	end
	loaded = true

	local ok, ffi = pcall(require, "ffi")
	if not ok then
		return
	end

	local cdef_ok = pcall(
		ffi.cdef,
		[[
		uint64_t display_tick;
		typedef struct {} Error;
		typedef struct {} win_T;
		typedef struct {
			int start;
			int level;
			int llevel;
			int lines;
		} foldinfo_T;
		foldinfo_T fold_info(win_T *wp, int lnum);
		win_T *find_window_by_handle(int Window, Error *err);
	]]
	)
	if not cdef_ok then
		return
	end

	C = ffi.C

	for sym in pairs(symbols) do
		symbols[sym] = pcall(function()
			return C[sym]
		end)
	end
end

--- Current display tick (bumped every redraw).
--- Returns 0 when FFI is unavailable — caller must treat 0 as a constant
--- (i.e. cache never auto-invalidates and relies on explicit drops).
---@return integer
function M.tick()
	load_ffi()
	if not C or not symbols.display_tick then
		return 0
	end
	return tonumber(C.display_tick) or 0
end

--- Fold info for `(win, lnum)`. Returns nil when FFI is unavailable or the
--- window handle cannot be resolved.
---@param win integer
---@param lnum integer
---@return { start: integer, level: integer, llevel: integer, lines: integer }?
function M.fold_info(win, lnum)
	load_ffi()
	if not C or not symbols.fold_info or not symbols.find_window_by_handle then
		return nil
	end
	local ffi = require("ffi")
	local err = ffi.new("Error")
	local wp = C.find_window_by_handle(win, err)
	if wp == nil then
		return nil
	end
	local info = C.fold_info(wp, lnum)
	return { start = info.start, level = info.level, llevel = info.llevel, lines = info.lines }
end

--- Feature-detection report for `:checkhealth`.
---@return { available: boolean, symbols: table<string, boolean> }
function M.report()
	load_ffi()
	return { available = C ~= nil, symbols = vim.deepcopy(symbols) }
end

return M
