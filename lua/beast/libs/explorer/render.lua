---@type Beast.Explorer.State
local state = require("beast.libs.explorer.state")
local config = require("beast.libs.explorer.config")

local M = {}

local styles = {
	compact = { indent = "  ", vertical = "│ ", branch = "├╴", last_branch = "└╴" },
	classic = { indent = "  ", vertical = "│ ", branch = "│ ", last_branch = "└╴" },
}

--- Build the tree-line prefix for `node`.
---
--- Depth-0 nodes (direct children of root) get no connector — they sit
--- flush under the uppercase root header with just a leading space.
---
--- Depth-1+ nodes get the standard box-drawing connectors:
---   Ancestor levels → "│ " (has more siblings) or "  " (was last)
---   Own level       → "├╴" (not last) or "└╴" (last)
---
--- The depth-0 ancestor indicator is intentionally skipped so that the
--- top-level items don't show a │ connecting them to the plain-text header.
---
---@param node Beast.Explorer.Node
---@return string
local function build_prefix(node)
  -- stylua: ignore
  if node.depth == 0 then return " " end  -- no connector for top-level items

	-- Collect `last` flags from depth-0 up to this node (inclusive).
	local levels = {} ---@type boolean[]
	local n = node
	while n.depth >= 0 do
		table.insert(levels, 1, n.last)
		n = state.tree.nodes[n.parent]
	end

	-- levels[1] = depth-0 ancestor's flag — skipped below
	-- levels[#levels] = this node's flag
	local prefix = " " -- leading padding
	local st = styles[config.style]
	for i = 2, #levels do -- start at 2 to skip the depth-0 indicator
		if i == #levels then
			prefix = prefix .. (levels[i] and st.last_branch or st.branch)
		else
			prefix = prefix .. (levels[i] and st.indent or st.vertical)
		end
	end
	return prefix
end

--- Build the lines and highlight specs for the current tree state.
--- Line 1 is always the root header; nodes occupy lines 2..N.
---@param nodes Beast.Explorer.Node[]
---@return string[], {line:integer,col_s:integer,col_e:integer,group:string}[]
function M.build(nodes)
	local lines = {} ---@type string[]
	local hls = {} ---@type {line:integer,col_s:integer,col_e:integer,group:string}[]

	-- Root header: " UPPERCASE-BASENAME" — no icon, plain text, visually distinct
	local root_name = string.upper(vim.fn.fnamemodify(state.view.cwd, ":t"))
	lines[1] = " " .. root_name
	hls[#hls + 1] = { line = 0, col_s = 0, col_e = #lines[1], group = "Directory" }

	local clipboard_paths = {} ---@type table<string, boolean>
	if state.clipboard then
		for _, p in ipairs(state.clipboard.paths) do
			clipboard_paths[p] = true
		end
	end

	local devicons_ok, devicons = pcall(require, "nvim-web-devicons")
	for _, node in ipairs(nodes) do
		local line_idx = #lines -- 0-indexed: lines[1] is already the header
		local prefix = build_prefix(node)

		-- Icon
		local icon_str = ""
		local icon_hl = nil ---@type string?

		if config.icons then
			if node.dir then
				icon_str = node.open and config.icon.dir_open or config.icon.dir_closed
				icon_hl = "Directory"
			else
				local icon, hl
				if devicons_ok then
					icon, hl = devicons.get_icon(node.name, nil, { default = true })
				end
				icon_str = icon or config.icon.file
				icon_hl = hl
			end
		end

		-- Clipboard indicator suffix
		local clip_suffix = ""
		if clipboard_paths[node.path] then
      clip_suffix = " " .. "(" .. state.clipboard.mode .. ")"
		end

		lines[#lines + 1] = prefix .. icon_str .. " " .. node.name .. clip_suffix

		-- Tree-line characters (Indent Markers) in a subtle colour
		hls[#hls + 1] = { line = line_idx, col_s = 0, col_e = #prefix, group = "NonText" }

		-- File / directory icon
		if icon_hl then
			hls[#hls + 1] = { line = line_idx, col_s = #prefix, col_e = #prefix + #icon_str, group = icon_hl }
		end
		-- Dim hidden files/dirs
		if node.hidden then
			hls[#hls + 1] = { line = line_idx, col_s = 0, col_e = #lines[line_idx + 1], group = "Comment" }
		end

		-- Highlight the clipboard suffix
		if clip_suffix ~= "" then
			local line_len = #lines[line_idx + 1]
			local suffix_hl = "NonText"
			hls[#hls + 1] = { line = line_idx, col_s = line_len - #clip_suffix, col_e = line_len, group = suffix_hl }
		end
	end

	return lines, hls
end

--- Write lines and highlights atomically to the explorer buffer.
---@param lines string[]
---@param hls {line:integer,col_s:integer,col_e:integer,group:string}[]
function M.write(lines, hls)
	-- Write lines + highlights atomically; ignore errors from a race-closed window
	pcall(function()
		vim.bo[state.view.buf].modifiable = true
		vim.api.nvim_buf_set_lines(state.view.buf, 0, -1, false, lines)
		vim.bo[state.view.buf].modifiable = false

		vim.api.nvim_buf_clear_namespace(state.view.buf, state.view.ns, 0, -1)
		for _, h in ipairs(hls) do
			pcall(vim.api.nvim_buf_set_extmark, state.view.buf, state.view.ns, h.line, h.col_s, {
				end_col = h.col_e,
				hl_group = h.group,
			})
		end
	end)
end

return M
