--- Debug action: dump the current node's metadata to a floating preview.
--- Useful for inspecting git status resolution (kind, phase, dim-variant
--- selection, badge glyph) and verifying tree shape during development.

local config = require("beast.libs.explorer.config")
local render = require("beast.libs.explorer.render")
local state = require("beast.libs.explorer.state")

local M = setmetatable({}, {
	__call = function(t, ...)
		return t.run(...)
	end,
})

---@param status? Beast.Explorer.GitStatus
---@return string
local function fmt_status(status)
	if not status then
		return "nil"
	end
	return string.format("{ kind = %q, phase = %q }", status.kind, tostring(status.phase))
end

---@param node Beast.Explorer.Node
---@return string[]
local function build_report(node)
	local lines = {}
	local function push(fmt, ...)
		lines[#lines + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt
	end

	push("── Node ──")
	push("path     : %s", node.path)
	push("name     : %s", node.name)
	push("type     : %s  (dir=%s)", node.type, tostring(node.dir))
	push("depth    : %d  last=%s  hidden=%s", node.depth, tostring(node.last), tostring(node.hidden))
	push("open     : %s  expanded=%s", tostring(node.open), tostring(node.expanded))
	push("parent   : %s", tostring(node.parent))
	push("children : %d", vim.tbl_count(node.children))

	push("")
	push("── Git ──")
	push("node.git_status   : %s", fmt_status(node.git_status))

	local direct = state.git.status and state.git.status[node.path]
	local agg = state.git.dir_status and state.git.dir_status[node.path]
	push("status[path]      : %s   (direct file/dir record)", fmt_status(direct))
	push("dir_status[path]  : %s   (aggregated from descendants)", fmt_status(agg))

	local hl = render.git_hl(node.git_status)
	push("resolved hl group : %s", tostring(hl))

	local glyph = nil
	if node.git_status and node.git_status.kind then
		local icons = config.icon and config.icon.git
		local g = icons and icons[node.git_status.kind]
		glyph = (g == nil or g == "") and "(hidden)" or g
	end
	push("badge glyph       : %s", tostring(glyph))

	-- Ancestor fallback chain (mirrors git.resolve logic)
	local nodes = state.tree and state.tree.nodes
	local chain = {}
	local p = node.parent
	while p do
		local anc = state.git.status and state.git.status[p]
		if anc then
			chain[#chain + 1] = string.format("  %s → %s", p, fmt_status(anc))
		end
		local pn = nodes and nodes[p]
		p = pn and pn.parent or nil
	end
	push("")
	push("── Ancestor status records ──")
	if #chain == 0 then
		push("  (none)")
	else
		for _, line in ipairs(chain) do
			push("%s", line)
		end
	end

	return lines
end

---@param lines string[]
local function open_float(lines)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].modifiable = false

	local width = 0
	for _, l in ipairs(lines) do
		if #l > width then
			width = #l
		end
	end
	width = math.min(width + 2, math.floor(vim.o.columns * 0.9))
	local height = math.min(#lines, math.floor(vim.o.lines * 0.8))

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		style = "minimal",
		border = "rounded",
		title = " Explorer debug ",
		title_pos = "center",
	})
	vim.wo[win].wrap = false
	vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true, silent = true })
	vim.keymap.set("n", "<esc>", "<cmd>close<cr>", { buffer = buf, nowait = true, silent = true })
end

function M.run()
	local node = state.current_node({ show_hidden = config.show_hidden })
	if not node then
		vim.notify("[explorer] no node under cursor", vim.log.levels.WARN)
		return
	end
	open_float(build_report(node))
end

return M
