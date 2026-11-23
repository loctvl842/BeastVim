-- Shared setup for BeastVim specs, see docs/development/testing.md.
--
--   local h = require('test.helper')
--   local n = h.n
--   before_each(h.clear)
--
-- Every spec runs its lib code in a child Nvim started by `h.clear()`, so
-- nothing leaks between tests and the lib is loaded the way it is in the
-- editor: from the repo's runtimepath, with the real `Util`/`Theme`/`Git`/`View`
-- globals that `beast.setup` publishes.
local n = require("test.functional.testnvim")()

local M = { n = n }

---Start a fresh child Nvim with the repo on its runtimepath.
---@param opts? { globals?: boolean } `globals = false` skips publishing `Util`, `Theme`, `Git` and `View`.
function M.clear(opts)
	n.clear()
	n.exec_lua(function(globals)
		vim.opt.runtimepath:prepend(vim.fn.getcwd())
		if globals then
			_G.Util = require("beast.util")
			_G.Theme = Util.mod("beast.theme")
			_G.Git = Util.mod("beast.libs.git")
			_G.View = Util.mod("beast.libs.view")
		end
	end, not (opts and opts.globals == false))
end

return M
