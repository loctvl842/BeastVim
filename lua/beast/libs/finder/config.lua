---@class Beast.Finder.Config
local defaults = {
	width = 0.8,
	height = 0.8,
	preview_ratio = 0.5,
	preview_image = true,
	preview_image_cell_ratio = 2.0,
	backdrop = 5,
	prompt_prefix = " ",
	selection_prefix = "▌",
	debounce = {
		normal_ms = 30,
		live_ms = 200,
		preview_ms = 60,
	},
	matcher = {
		smartcase = true,
		ignorecase = true,
	},
	engine = {
		enabled = true,
		max_files = 100000,
		max_file_size = 1024 * 1024,
		max_survivors = 5000,
	},
	actions = {},
	-- Chains (`chains.lua`): the edges are built in; these only choose among them (see
	-- `docs/chains.md` for the edge ids and their default keys). Invalid settings raise at setup.
	chains = {
		-- Keys that go back one level (at least one; a key the picker already uses raises).
		-- "<BS>" goes back only on an empty prompt, else it deletes a character.
		back = { "<BS>", "<C-o>" },
		-- By edge id ("from|to"): `false` switches the edge off, `{ key = "<M-g>" }` gives it another key.
		-- An edge left out keeps its default key. Two edges from one picker cannot share a key, and an
		-- edge key cannot also be a back key.
		---@type table<string, false|{ key?: string }>
		edges = {},
	},
}

---@type Beast.Finder.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param opts? Beast.Finder.Config
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
		error(string.format("beast.finder.config is read-only; cannot assign '%s'. Use setup().", tostring(key)), 2)
	end,
})

return M
