local Filter = require("beast.libs.finder.filter")
local State = require("beast.libs.finder.state")
local source_registry = require("beast.libs.finder.source")

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
	require("beast.libs.finder.source.live_grep.engine.index").setup()
	initialized = true
end

---@param source_name Beast.Finder.Source
---@param opts Beast.Finder.Opts
local function open_picker(source_name, opts)
	state = State(source_name, opts)
	require("beast.libs.finder.keymaps").mount(state)
	require("beast.libs.finder.autocmds").mount(state)
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

	-- State:new() used to guarantee any open picker resets on every open()
	-- call; the auto_select branch below can skip State entirely, so that
	-- guarantee is made explicit here instead.
	M.close()

	local source = source_registry[source_name]
	if source.auto_select then
		-- Pre-flight: run the source to completion before any picker window
		-- exists. A single result jumps directly (no picker ever shown); more
		-- than one falls through to the normal picker.
		local filter = Filter({ cwd = opts.cwd })
		local main_win = View.win.find_normal()
		require("beast.libs.finder.preflight").check(source, filter, function(items)
			if #items == 1 then
				require("beast.libs.finder.action").open_file({ main_win = main_win } --[[@as Beast.Finder.State]], items[1])
			elseif #items > 1 then
				open_picker(source_name, opts)
			end
		end)
		return
	end

	open_picker(source_name, opts)
end

function M.close()
	if state then
		state:reset()
	end
end

return M
