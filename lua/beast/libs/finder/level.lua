--- One search: a source, the query that holds its results, and the engine (pipeline) that runs it.
--- Also remembers what a stack of levels has to put back when this one is shown again: the prompt
--- text, title, count label and the list position. No windows live here - a Session binds a level
--- to its windows by giving it a host (see host.lua).
local Query = require("beast.libs.finder.query")
local config = require("beast.libs.finder.config")
local pipeline_registry = require("beast.libs.finder.pipeline")
local source_registry = require("beast.libs.finder.source")

---@class Beast.Finder.Level
---@field source Beast.Finder.ASource
---@field query Beast.Finder.Query
---@field engine Beast.Finder.Pipeline.Match|Beast.Finder.Pipeline.Stream
---@field title string prompt title (a picker in the `cards` layout shows none)
---@field text string prompt text, kept up to date so the level can be shown again
---@field count? string count label last shown
---@field cursor integer list cursor to restore
---@field offset integer list scroll offset to restore
---@field initial_query? string live sources: prompt text the level opens with, searched at once
---@field debounce_ms? integer how long typing must pause before this level searches
---@field crumb? string name of the picker this level was opened from ("<BS> back to <crumb>")
---@field host? Beast.Finder.Host set by the Session that shows the level
local M = {}
M.__index = M

---@class Beast.Finder.LevelOpts: Beast.Finder.QueryOpts
---@field title? string overrides the source's title
---@field crumb? string

---@param source_name Beast.Finder.Source
---@param opts? Beast.Finder.LevelOpts
---@return Beast.Finder.Level
function M.new(source_name, opts)
	opts = opts or {}
	local source = source_registry[source_name]
	local readable = source_name:gsub("_", " ")
	return setmetatable({
		source = source,
		query = Query(source, { cwd = opts.cwd, preloaded_items = opts.preloaded_items, limit = opts.limit, files = opts.files, ctx = opts.ctx }),
		engine = source.live and pipeline_registry.stream or pipeline_registry.match,
		title = opts.title or (source.title and source.title() or (readable:sub(1, 1):upper() .. readable:sub(2))),
		crumb = opts.crumb,
		text = "",
		cursor = 1,
		offset = 0,
		initial_query = source.live and source.initial_query or nil,
		debounce_ms = source.debounce_ms or (source.live and config.debounce.live_ms or nil),
	}, M)
end

--- Begin loading (match sources) or run the default query (live sources that have one).
function M:start()
	if self.initial_query then
		self.text = self.initial_query
	end
	self.engine.start(self.query, self.host)
end

--- The prompt text changed.
---@param text string
function M:run(text)
	self.text = text
	self.query.filter:update(text)
	self.engine.run(self.query, self.host)
end

--- The source's data changed: load or search again.
function M:reload()
	self.engine.reload(self.query, self.host)
end

--- Abort whatever is running; late answers are dropped.
function M:stop()
	self.engine.abort(self.query)
end

return M
