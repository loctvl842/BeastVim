---@class Beast.Explorer.Config
local defaults = {
	style = "classic",
	width = 40,
	side = "left",
	show_hidden = false,
	icons = true,
	padding = 1, -- Left padding for whole explorer (in spaces).
	padding_right = 1, -- Right padding for badges / virtual text (in spaces).
	-- Sticky ancestor headers: float at the top of the explorer that pins
	-- the parent directories of the topmost visible node when they scroll
	-- out of view. Set false to disable entirely.
	sticky = true,
	icon = {
		dir_open = "", --  "󰝰", -- nf-md-folder_open
		dir_closed = "", -- "󰉋", -- nf-md-folder
		file = "󰈙", -- fallback when devicons has no match
		-- Per-status glyph for the right-aligned git badge.
		-- Behavior:
		--   * Empty string ("") hides the badge for that status; name coloring still applies.
		--   * Unset keys fall through to defaults via tbl_deep_extend.
		--   * Highlight groups (BeastExplorerGit*) are unchanged; only the glyph is configurable.
		git = {
			conflict = "C",
			modified = "M",
			renamed = "R",
			deleted = "D",
			added = "A",
			untracked = "U",
			ignored = "!",
		},
	},
	mappings = {
		["<CR>"] = "open",
		["a"] = "create",
		["d"] = "delete",
		["r"] = "rename",
		["<bs>"] = "navigate_up",
		["."] = "set_root",
		["H"] = "show_hidden",
		["x"] = "cut_to_clipboard",
		["y"] = "copy_to_clipboard",
		["p"] = "paste_from_clipboard",
	},
}

---@type Beast.Explorer.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

function methods.toggle_hidden()
	cfg.show_hidden = not cfg.show_hidden
end

--- Resolve a file-name to its devicons glyph and highlight group, falling
--- back to `cfg.icon.file` when nvim-web-devicons isn't available or has no
--- match for the name.
---@param name string
---@return string icon, string? hl
function methods.file_icon(name)
	if methods._devicons == nil then
		local ok, mod = pcall(require, "nvim-web-devicons")
		methods._devicons = ok and mod or false
	end

	if methods._devicons then
		local icon, hl = methods._devicons.get_icon(name, nil, { default = true })
		if icon then
			return icon, hl
		end
	end
	return cfg.icon.file, nil
end

---@param opts? Beast.Explorer.Config
function methods.setup(opts)
	opts = opts or {}
	cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
end

local M = setmetatable({}, {
	__index = function(_, key)
		if methods[key] ~= nil then
			return methods[key]
		end
		return cfg[key]
	end,
	__newindex = function(_, key, _)
		error(string.format("beast.explorer.config is read-only; cannot assign '%s' directly. Use setup() instead.", tostring(key)), 2)
	end,
})

return M
