-- Highlight refresh pipeline.
--
-- Owns three things:
--   1. `M.highlight_modules` — the registry of `<lib>/highlights.lua` modules
--      visited on every `ColorScheme` event.
--   2. `M.apply_highlights(mod)` / `M.reload_highlights()` — the dispatcher
--      that loads each module via `Util.mod`, calls its pure `M.get()`,
--      merges the results, and applies them in a single `nvim_set_hl` pass.
--      See ADR-026 for the contract.
--   3. `M.setup()` — registers the `ColorScheme` autocmd that wires
--      `Palette.refresh()` + `M.reload_highlights()` together.
--
-- Each lib's `setup()` calls `require("beast").apply_highlights("X.highlights")`
-- at first-load (beast/init.lua re-exports `apply_highlights` from here).

local M = {}

--- Registry of highlight modules to reload on ColorScheme change.
--- Lazy-loaded libs register their highlights dynamically via packer.lazy().
---@type string[]
M.highlight_modules = {
	"beast.palette.highlights",
	"beast.libs.confirm.highlights",
	"beast.libs.explorer.highlights",
	"beast.libs.finder.highlights",
	"beast.libs.key.highlights",
	"beast.libs.notify.highlights",
	"beast.libs.packer.highlights",
	"beast.libs.statusline.highlights",
	"beast.libs.statuscolumn.highlights",
	"beast.libs.git.highlights",
	"beast.libs.breadcrumb.highlights",
	"beast.libs.tabline.highlights",
	"beast.libs.toast.highlights",
	"beast.libs.indent.highlights",
	"beast.libs.treesitter.highlights",
}

--- Highlight modules that are only needed for builtin colorschemes
--- (third-party schemes define their own treesitter highlights).
---@type table<string, boolean>
local builtin_only_highlights = {
	["beast.libs.treesitter.highlights"] = true,
}

--- Apply a single highlight module immediately. Used at lib `setup()` time
--- so freshly-loaded libs see their highlights before the next ColorScheme
--- event triggers a full `reload_highlights()`.
---@param mod_name string e.g. "beast.libs.explorer.highlights"
function M.apply_highlights(mod_name)
	local ok, mod = pcall(Util.mod, mod_name)
	if not (ok and type(mod) == "table" and type(mod.get) == "function") then
		return
	end
	local ok_get, groups = pcall(mod.get)
	if not (ok_get and type(groups) == "table") then
		return
	end
	for group, hl in pairs(groups) do
		vim.api.nvim_set_hl(0, group, hl)
	end
	if type(mod.post_apply) == "function" then
		pcall(mod.post_apply)
	end
end

--- Reload all Beast lib highlights.
--- Skips modules whose parent lib hasn't been loaded yet.
--- Skips treesitter highlights for third-party colorschemes.
---
--- Each highlight module returns `{ get(), post_apply?() }`. We collect groups
--- from every gated module first, then push them via a single nvim_set_hl
--- pass, then run any post_apply hooks (statusline redraw, icon cache, etc.).
function M.reload_highlights()
	local is_builtin = Palette.is_builtin_colorscheme()
	local merged = {}
	local post_hooks = {}
	for _, mod_name in ipairs(M.highlight_modules) do
		-- stylua: ignore
		if not is_builtin and builtin_only_highlights[mod_name] then goto continue end
		local parent = mod_name:gsub("%.highlights$", "")
		-- stylua: ignore
		if not package.loaded[parent] then goto continue end
		local ok, mod = pcall(Util.mod, mod_name)
		if ok and type(mod) == "table" and type(mod.get) == "function" then
			local ok_get, groups = pcall(mod.get)
			if ok_get and type(groups) == "table" then
				for group, hl in pairs(groups) do
					merged[group] = hl
				end
			end
			if type(mod.post_apply) == "function" then
				post_hooks[#post_hooks + 1] = mod.post_apply
			end
		end
		::continue::
	end
	for group, hl in pairs(merged) do
		vim.api.nvim_set_hl(0, group, hl)
	end
	for _, hook in ipairs(post_hooks) do
		pcall(hook)
	end
end

--- Register the ColorScheme autocmd. Deferred via `vim.schedule` so palette
--- refresh + apply happen after the colorscheme command finishes drawing.
function M.setup()
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("BeastPalette", { clear = true }),
		callback = function()
			vim.schedule(function()
				Palette.refresh()
				M.reload_highlights()
			end)
		end,
	})
end

return M
