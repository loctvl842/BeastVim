local Filter = require("beast.libs.finder.filter")
local Session = require("beast.libs.finder.session")
local source_registry = require("beast.libs.finder.source")

local M = {}

---@type Beast.Lib.Meta
M.meta = { name = "finder", description = "Fuzzy finder picker (files, grep, LSP, commands)" }

local initialized = false

---@param opts? Beast.Finder.Config
function M.setup(opts)
	require("beast.libs.finder.config").setup(opts)
	require("beast").apply_highlights("beast.libs.finder.highlights")
	require("beast.libs.finder.source.live_grep.engine.index").setup()
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

	-- Session.open() closes any open picker; the auto_select branch below can skip
	-- the Session entirely, so that guarantee is made explicit here instead.
	M.close()

	local source = source_registry[source_name]
	if source.check and not source.check() then
		return
	end
	if source.auto_select then
		-- Pre-flight: run the source to completion before any picker window
		-- exists. A single result jumps directly (no picker ever shown); more
		-- than one falls through to the normal picker.
		local filter = Filter({ cwd = opts.cwd })
		local main_win = View.win.find_normal()
		local finder_status = require("beast.libs.finder.status")
		finder_status.start(source.label)
		require("beast.libs.finder.preflight").check(source, filter, function(items)
			finder_status.stop()
			if #items == 1 then
				require("beast.libs.finder.action").open_file(main_win, items[1])
			elseif #items > 1 then
				opts.preloaded_items = items
				Session.open(source_name, opts)
			end
		end)
		return
	end

	Session.open(source_name, opts)
end

--- Every chain the finder supports: the pickers a picker can lead to (see chains.lua).
---@return Beast.Finder.Edge[]
function M.chains()
	return require("beast.libs.finder.chains")
end

function M.close()
	Session.close_current()
end

return M
