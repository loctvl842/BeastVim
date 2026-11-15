--- The map of chains: what a picker can lead to next. One row per edge (`from` source to `to` source).
--- The edges are built in and closed: no other pair is supported (`chain.edge` raises for it).
---
--- `open(ctx)` builds the next level: a table of level options (see `Beast.Finder.LevelOpts`), a
--- string (a message shown to the user, nothing opens) or nil ("nothing to open from here").
--- `hint(ctx)` is the text shown after the key in the hint line under the picker; nil hides it.
---@class Beast.Finder.ChainCtx
---@field items? Beast.Finder.Item[] every item that matches the prompt (only given to `open`; nil while the picker is still working)
---@field selected? Beast.Finder.Item the highlighted item
---@field total integer how many items match the prompt
---@field filter Beast.Finder.Filter

---@class Beast.Finder.Edge
---@field from Beast.Finder.Source
---@field to Beast.Finder.Source
---@field key? string key that follows the edge (default `<C-g>`)
---@field crumb string name of the `from` picker, shown as "<BS> back to <crumb>"
---@field hint fun(ctx: Beast.Finder.ChainCtx): string?
---@field open fun(ctx: Beast.Finder.ChainCtx): Beast.Finder.LevelOpts|string|nil

--- Paths of the items that are files, without repeats.
---@param items Beast.Finder.Item[]
---@return string[]
local function file_paths(items)
	local seen, paths = {}, {}
	for _, item in ipairs(items) do
		if item.file and not seen[item.file] then
			seen[item.file] = true
			paths[#paths + 1] = item.file
		end
	end
	return paths
end

---@param ctx Beast.Finder.ChainCtx
---@return string?
local function grep_files(ctx)
	return ctx.total > 0 and ("grep " .. ctx.total .. " files") or nil
end

--- The grep over the files behind the matching items, titled "<N> <what> › Live Grep".
---@param what string what the files are called ("Files", "Buffers", ...)
---@return fun(ctx: Beast.Finder.ChainCtx): Beast.Finder.LevelOpts?
local function scope_files(what)
	return function(ctx)
		local paths = file_paths(ctx.items)
		if #paths == 0 then
			return nil
		end
		return { files = paths, title = ("%d %s › Live Grep"):format(#paths, what) }
	end
end

---@param ctx Beast.Finder.ChainCtx
---@return string?
local function grep_help(ctx)
	return ctx.total > 0 and "grep the matching help pages" or nil
end

---@type Beast.Finder.Edge[]
return {
	{ from = "files", to = "live_grep", crumb = "Files", hint = grep_files, open = scope_files("Files") },
	{ from = "buffers", to = "live_grep", crumb = "Buffers", hint = grep_files, open = scope_files("Buffers") },
	{ from = "help_tags", to = "live_grep", crumb = "Help", hint = grep_help, open = scope_files("Help Files") },
}
