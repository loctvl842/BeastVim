--- Type definition only — no logic lives here.
--- Extend Beast.View with the fields the explorer panel needs.

local View = require("beast.libs.view")

---@class Beast.Explorer.View : Beast.View
---@field ns  integer  extmark namespace for highlight decorations
---@field cwd string   absolute path of the root directory being shown
local ExplorerView = View:extend(function(obj, ns, cwd)
	obj.ns = ns
	obj.cwd = cwd
end)

-- Constructor signature: ExplorerView(buf, win, ns, cwd)
-- Inherited from Beast.View:
--   view:is_valid() → boolean
--   view:close()

return ExplorerView
