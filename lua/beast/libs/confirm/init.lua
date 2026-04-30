local ui = require("beast.libs.confirm.ui")

local M = setmetatable({}, {
	__call = function(t, ...)
		return t.run(...)
	end,
})

function M.setup()
	require("beast.libs.confirm.highlights")
end

function M.run(opts, cb)
	opts = opts or {}
	local view = ui.create(opts)
	-- Default to "no"
	local selected = opts.default ~= nil and opts.default or 2
	ui.render(view, selected)
	vim.cmd("redraw")

	local cancelled = ui.run_modal_loop(view, selected)
	ui.close(view)
	if cb then
		cb(cancelled)
	end
end

return M
