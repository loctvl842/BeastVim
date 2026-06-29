local State = require("beast.libs.finder.state")

local M = {}

---@type Beast.Lib.Meta
M.meta = { name = "finder", description = "Fuzzy finder picker (files, grep, LSP, commands)" }

local initialized = false
---@type Beast.Finder.State?
local state = nil

---@param opts? Beast.Finder.Config
function M.setup(opts)
	require("beast.libs.finder.config").setup(opts)
	require("beast").apply_highlights("beast.libs.finder.highlights")
	require("beast.libs.finder.engine.debug").register()
	initialized = true
end

---@param source_name Beast.Finder.Source
---@param opts? Beast.Finder.Opts
function M.open(source_name, opts)
	opts = opts or {}

	-- LSP keymaps can fire before the packer.lazy `keys` trigger initializes
	-- the finder. Run setup with defaults so config + highlights are ready.
	if not initialized then
		M.setup()
	end

	state = State(source_name, opts)
	require("beast.libs.finder.keymaps").mount(state)
	require("beast.libs.finder.autocmds").mount(state)
end

function M.close()
	if state then
		state:reset()
	end
end

return M
