---@class Beast.Explorer.Config
---@field style           "classic"|"compact"
---@field width           integer        panel width in columns
---@field side            "left"|"right" which side to open the split
---@field show_hidden     boolean        show dot-files
---@field icons           boolean        nerd-font glyphs (requires nvim-web-devicons)
---@field git             boolean        git-status indicators
---@field icon_dir_open   string         glyph for an open directory
---@field icon_dir_closed string         glyph for a closed directory
---@field icon_file       string         fallback glyph for files without a devicon
---@field icon_git  table<string, {[1]:string,[2]:string}> xy-code → {glyph, hl-group}

local defaults = {
	style = "classic",
	width = 40,
	side = "left",
	show_hidden = false,
	icons = true,
	git = true,
	icon = {
		dir_open = "", --  "󰝰", -- nf-md-folder_open
		dir_closed = "", -- "󰉋", -- nf-md-folder
		file = "󰈙", -- fallback when devicons has no match
	},
	icon_git = {
		["M "] = { "●", "DiagnosticOk" }, -- staged
		[" M"] = { "●", "DiagnosticWarn" }, -- unstaged
		["MM"] = { "●", "DiagnosticWarn" }, -- staged + unstaged
		["A "] = { "●", "DiagnosticOk" }, -- added
		["??"] = { "?", "DiagnosticHint" }, -- untracked
		["!!"] = { "", "Comment" }, -- ignored
		[" D"] = { "✗", "DiagnosticError" }, -- deleted (unstaged)
		["D "] = { "✗", "DiagnosticError" }, -- deleted (staged)
	},
	mappings = {
		["<CR>"] = "open",
		["a"] = "create",
    ["d"] = "delete",
    ["r"] = "rename",
	},
}

---@type Beast.Explorer.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param opts? Beast.Explorer.Config
function methods.setup(opts)
	cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

local M = setmetatable({}, {
	__index = function(_, key)
		if methods[key] ~= nil then
			return methods[key]
		end
		return cfg[key]
	end,
	__newindex = function(_, key, _)
		error(
			string.format(
				"beast.explorer.config is read-only; cannot assign '%s' directly. Use setup() instead.",
				tostring(key)
			),
			2
		)
	end,
})

return M
