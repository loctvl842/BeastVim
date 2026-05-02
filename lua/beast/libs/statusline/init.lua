local config = require("beast.libs.statusline.config")
local context = require("beast.libs.statusline.context")
local truncate = require("beast.libs.statusline.truncate")
local util = require("beast.libs.statusline.util")

-- =========================================================================
-- State (only this file mutates it)
-- =========================================================================

---@alias Beast.Statusline.Region "left"|"center"|"right"

local state = {
	---@type integer
	next_id = 0,
	---@type table<integer, Beast.Statusline.ComponentSpec>
	components = {},
	---@type table<Beast.Statusline.Region, integer[]>
	region_ids = { left = {}, center = {}, right = {} },
}

-- =========================================================================
-- Helpers
-- =========================================================================

---@param specs Beast.Statusline.ComponentSpec[]
---@return integer[]
local function register_region(specs)
	local ids = {}
	for _, spec in ipairs(specs or {}) do
		state.next_id = state.next_id + 1
		state.components[state.next_id] = spec
		ids[#ids + 1] = state.next_id
	end
	return ids
end

-- =========================================================================
-- Component evaluation (with cache + error isolation)
-- =========================================================================
---@param comp_id integer
---@param ctx Beast.Statusline.Context
---@return Beast.Statusline.Fragment[]?
local function eval_component(comp_id, ctx)
	local spec = state.components[comp_id]
  -- stylua: ignore
	if spec.condition and not spec.condition(ctx) then return nil end

	local ok, fragments = pcall(spec.provider, ctx)
  -- stylua: ignore
	if not ok or fragments == nil then return nil end

	-- Pre-compute widths once so truncation/assembly never call strdisplaywidth twice.
	for _, f in ipairs(fragments) do
		if not f.width then
			f.width = vim.fn.strdisplaywidth(f.text or "")
		end
	end

	return fragments
end

---@param ids integer[]
---@param ctx Beast.Statusline.Context
---@return Beast.Statusline.VisibleItem[]
local function build_visible_items(ids, ctx)
	local items = {}
	for _, comp_id in ipairs(ids) do
		local fragments = eval_component(comp_id, ctx)
		if fragments and #fragments > 0 then
			items[#items + 1] = { spec = state.components[comp_id], fragments = fragments }
		end
	end
	return items
end

-- =========================================================================
-- Autocmd registration (lazy, idempotent)
-- =========================================================================

---Split an update entry into its autocmd event and optional pattern.
---
---Each string in a component's `update` list is an autocmd event name, optionally followed
---by a space and a pattern. The pattern is passed to `nvim_create_autocmd` as `pattern`
---(the same field you'd use with `:autocmd`).
---
---Examples:
---  "BufEnter"                        → event = "BufEnter",  pattern = nil
---  "User BeastStatuslineGitChanged"  → event = "User",      pattern = "BeastStatuslineGitChanged"
---  "FileType lua"                    → event = "FileType",   pattern = "lua"
---
---@param ev string  A single entry from the component's `update` list.
---@return string event   The Neovim autocmd event name (first word).
---@return string? pattern  The autocmd pattern (everything after the first space), or nil.
local function split_event(ev)
	local space = ev:find(" ")
	if space then
		return ev:sub(1, space - 1), ev:sub(space + 1)
	end
	return ev, nil
end

local function register_event_autocmds()
	-- Map of declared event -> list of comp_ids interested in it.
	local event_to_comps = {}
	for comp_id, spec in pairs(state.components) do
		for _, ev in ipairs(spec.update or {}) do
			event_to_comps[ev] = event_to_comps[ev] or {}
			event_to_comps[ev][#event_to_comps[ev] + 1] = comp_id
    end
  end

	for ev, _ in pairs(event_to_comps) do
		local event_name, pattern = split_event(ev)
		vim.api.nvim_create_autocmd(event_name, {
			group = state.augroup,
			pattern = pattern,
			callback = function()
				vim.cmd("redrawstatus")
			end,
		})
	end
end

local function ensure_autocmds()
  -- stylua: ignore
	if state.augroup then return end

	state.augroup = vim.api.nvim_create_augroup("BeastStatusline", { clear = true })

	register_event_autocmds()

	-- NOTE: ColorScheme refresh is intentionally NOT handled here. The Beast highlight
	-- registry (see beast/init.lua) re-requires beast.libs.statusline.highlights AFTER
	-- Palette.refresh() runs, which clears our caches at the right moment.

	-- Free per-buffer / per-window cache slots when their owners go away.
	-- Always redrawstatus afterwards: Neovim caches the `%!` result string, so without an
	-- explicit redraw a stale render (e.g. one captured mid-toast-teardown) would persist
	-- on screen until the next event-driven invalidation.
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = state.augroup,
		callback = function()
			vim.cmd("redrawstatus")
		end,
	})
	vim.api.nvim_create_autocmd("WinClosed", {
		group = state.augroup,
		callback = function()
			vim.cmd("redrawstatus")
		end,
	})
end

-- =========================================================================
-- Public API
-- =========================================================================

local M = {}

---@param opts? Beast.Statusline.Config
function M.setup(opts)
	config.setup(opts)
	state.region_ids.left = register_region(config.left)
	state.region_ids.center = register_region(config.center)
	state.region_ids.right = register_region(config.right)
  ensure_autocmds()
	vim.o.statusline = "%!v:lua.require'beast.libs.statusline'.render()"
end

---Render the statusline. Called by Neovim each time it decides to redraw the bar.
---@return string
function M.render()
	local ctx = context.build()
	local regions = {
		left = build_visible_items(state.region_ids.left, ctx),
		center = build_visible_items(state.region_ids.center, ctx),
		right = build_visible_items(state.region_ids.right, ctx),
	}
	regions = truncate.fit(regions, ctx.width, config.separator, config.default_priority)

	local sep = config.separator
	local parts = {}

	if config.truncate_marker and config.truncate_marker ~= "" then
		parts[#parts + 1] = config.truncate_marker
	end

	local bg = ctx.is_active and "StatusLine" or "StatusLineNC"
	if bg and bg ~= "" then
		parts[#parts + 1] = "%#" .. bg .. "#"
	end

	parts[#parts + 1] = util.assemble(regions.left, sep)
	parts[#parts + 1] = "%="
	parts[#parts + 1] = util.assemble(regions.center, sep)
	parts[#parts + 1] = "%="
	parts[#parts + 1] = util.assemble(regions.right, sep)

	local result = table.concat(parts)
	return result
end

return M
