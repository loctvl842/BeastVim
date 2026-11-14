--- Explorer modes: `state.mode` names what the explorer is showing ("normal"
--- is the plain tree). A mode module exposes `stop()` and optionally
--- `decorate(lines, hls, badges, nodes)`; core code only talks to this registry.
local state = require("beast.libs.explorer.state")

local M = {}

---@type table<string, string>  mode name -> module
local MODES = {
	search = "beast.libs.explorer.search",
}

---@return table?
local function active()
	local module = MODES[state.mode]
	return module and require(module) or nil
end

--- Add the active mode's marks to a freshly built render.
function M.decorate(lines, hls, badges, nodes)
	local mode = active()
	if mode and mode.decorate then
		mode.decorate(lines, hls, badges, nodes)
	end
end

--- Return to the normal tree (no-op when already there).
function M.leave()
	local mode = active()
	if mode then
		mode.stop()
	end
end

return M
