local config = require("beast.libs.explorer.config")
local state = require("beast.libs.explorer.state")

local M = {}

local styles = {
	compact = { indent = "  ", vertical = "│ ", branch = "├╴", last_branch = "└╴" },
	classic = { indent = "  ", vertical = "│ ", branch = "│ ", last_branch = "└╴" },
}

-- Badge character → highlight group for name coloring and virt_text.
local GIT_HL = {
	C = "BeastExplorerGitConflict",
	M = "BeastExplorerGitModified",
	R = "BeastExplorerGitRenamed",
	D = "BeastExplorerGitDeleted",
	A = "BeastExplorerGitAdded",
	U = "BeastExplorerGitUntracked",
	["!"] = "BeastExplorerGitIgnored",
}

-- Badge character → semantic key for looking up the user-configurable glyph.
local GIT_ICON_KEY = {
	C = "conflict",
	M = "modified",
	R = "renamed",
	D = "deleted",
	A = "added",
	U = "untracked",
	["!"] = "ignored",
}

--- Resolve the user-configured icon for a git badge.
--- Returns nil when the badge is nil/unknown or the user mapped it to an
--- empty string (= "hide this badge").
---@param badge? string
---@return string?
local function git_icon(badge)
	-- stylua: ignore
	if not badge then return nil end
	local key = GIT_ICON_KEY[badge]
	-- stylua: ignore
	if not key then return nil end
	local icons = config.icon and config.icon.git
	local glyph = icons and icons[key]
	if glyph == nil or glyph == "" then
		return nil
	end
	return glyph
end

--- Resolve the highlight group for a git badge character.
--- Returns nil when the badge is nil or unrecognized.
---@param badge? string
---@return string?
function M.git_hl(badge)
	-- stylua: ignore
	if not badge then return nil end
	return GIT_HL[badge]
end

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
function M.build_prefix(node)
  -- stylua: ignore
  if node.depth == 0 then return string.rep(" ", config.padding)  end  -- no connector for top-level items

	-- Collect `last` flags from depth-0 up to this node (inclusive).
	local levels = {} ---@type boolean[]
	while node.depth >= 0 do
		table.insert(levels, 1, node.last)
		node = state.tree.nodes[node.parent]
	end

	-- levels[1] = depth-0 ancestor's flag — skipped below
	-- levels[#levels] = this node's flag
	local prefix = string.rep(" ", config.padding) -- leading padding
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

--- Build prefixes for all nodes incrementally using a parent-prefix cache.
--- Avoids the O(depth) ancestor walk per node by building child prefixes
--- from their parent's cached "continuation" prefix.
---@param nodes Beast.Explorer.Node[]
---@return table<string, string>  path → prefix
function M.build_prefixes(nodes)
	local st = styles[config.style]
	local pad = string.rep(" ", config.padding)
	local cache = {} ---@type table<string, string>  path → continuation prefix

	-- The continuation prefix is everything a child inherits from its parent:
	-- parent's continuation + the connector segment for the parent's own level.
	-- The child then appends its own connector (branch or last_branch).

	local result = {} ---@type table<string, string>

	for _, node in ipairs(nodes) do
		if node.depth == 0 then
			result[node.path] = pad
			-- Continuation for depth-0 nodes: just padding (no connector at depth-0)
			cache[node.path] = pad
		else
			local parent_cont = cache[node.parent] or pad
			-- Own connector
			local own = node.last and st.last_branch or st.branch
			result[node.path] = parent_cont .. own
			-- Continuation for children: what comes before child's own connector
			local segment = node.last and st.indent or st.vertical
			cache[node.path] = parent_cont .. segment
		end
	end

	return result
end

--- Build the lines and highlight specs for the current tree state.
--- Line 1 is always the root header; nodes occupy lines 2..N.
---@param nodes Beast.Explorer.Node[]
---@return string[], {line:integer,col_s:integer,col_e:integer,group:string}[], {line:integer,text:string,hl:string}[]
function M.build(nodes)
	local lines = {} ---@type string[]
	local hls = {} ---@type {line:integer,col_s:integer,col_e:integer,group:string}[]
	local badges = {} ---@type {line:integer,text:string,hl:string}[]

	-- Root header: " UPPERCASE-BASENAME" — no icon, plain text, visually distinct
	local root_name = string.upper(vim.fn.fnamemodify(state.tree.root.path, ":t"))
	lines[1] = " " .. root_name
	hls[#hls + 1] = { line = 0, col_s = 0, col_e = #lines[1], group = "BeastExplorerTitle" }

	local clipboard_paths = {} ---@type table<string, boolean>
	if state.clipboard then
		for _, p in ipairs(state.clipboard.paths) do
			clipboard_paths[p] = true
		end
	end

	-- Build all prefixes in one pass (O(n) instead of O(n*depth))
	local prefixes = M.build_prefixes(nodes)

	for _, node in ipairs(nodes) do
		local line_idx = #lines -- 0-indexed for extmarks
		local prefix = prefixes[node.path]

		-- Icon
		local icon_str = ""
		local icon_hl = nil ---@type string?

		if config.icons then
			if node.dir then
				icon_str = node.open and config.icon.dir_open or config.icon.dir_closed
				icon_hl = "BeastExplorerDir"
			else
				icon_str, icon_hl = config.file_icon(node.name)
			end
		end

		-- Clipboard indicator suffix
		local clip_suffix = ""
		if clipboard_paths[node.path] then
			clip_suffix = " " .. "(" .. state.clipboard.mode .. ")"
		end

		lines[#lines + 1] = prefix .. icon_str .. " " .. node.name .. clip_suffix

		-- Tree-line characters (Indent Markers) in a subtle colour
		hls[#hls + 1] = { line = line_idx, col_s = 0, col_e = #prefix, group = "BeastExplorerIndent" }

		-- File / directory icon
		if icon_hl then
			hls[#hls + 1] = { line = line_idx, col_s = #prefix, col_e = #prefix + #icon_str, group = icon_hl }
		end

		-- File name
		if not node.dir then
			local name_s = #prefix + #icon_str + 1 -- +1 for the space after icon
			local name_hl = "BeastExplorerFile"
			-- Git status overrides the default file color
			if node.git_status and GIT_HL[node.git_status] then
				name_hl = GIT_HL[node.git_status]
			end
			hls[#hls + 1] = { line = line_idx, col_s = name_s, col_e = name_s + #node.name, group = name_hl }
		else
			-- Directory name: override with propagated git status color
			if node.git_status and GIT_HL[node.git_status] then
				local name_s = #prefix + #icon_str + 1
				hls[#hls + 1] = { line = line_idx, col_s = name_s, col_e = name_s + #node.name, group = GIT_HL[node.git_status] }
			end
		end

		-- Git badge (right-aligned virt_text) — only on files, not directories
		if node.git_status and GIT_HL[node.git_status] and not node.dir then
			local glyph = git_icon(node.git_status)
			if glyph then
				badges[#badges + 1] = { line = line_idx, text = glyph, hl = GIT_HL[node.git_status] }
			end
		end
		-- Dim hidden files/dirs
		if node.hidden then
			hls[#hls + 1] = { line = line_idx, col_s = 0, col_e = #lines[line_idx + 1], group = "BeastExplorerComment" }
		end

		-- Highlight the clipboard suffix
		if clip_suffix ~= "" then
			local line_len = #lines[line_idx + 1]
			local suffix_hl = "BeastExplorerClip"
			hls[#hls + 1] = { line = line_idx, col_s = line_len - #clip_suffix, col_e = line_len, group = suffix_hl }
		end
	end

	return lines, hls, badges
end

--- Write lines and highlights atomically to the explorer buffer.
---@param lines string[]
---@param hls {line:integer,col_s:integer,col_e:integer,group:string}[]
---@param badges? {line:integer,text:string,hl:string}[]
function M.write(lines, hls, badges)
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

		-- Git status badges as right-aligned virtual text
		if badges then
			local rpad = string.rep(" ", config.padding_right or 0)
			for _, b in ipairs(badges) do
				pcall(vim.api.nvim_buf_set_extmark, state.view.buf, state.view.ns, b.line, 0, {
					virt_text = { { b.text, b.hl }, { rpad } },
					virt_text_pos = "right_align",
					hl_mode = "combine",
				})
			end
		end
	end)
end

return M
