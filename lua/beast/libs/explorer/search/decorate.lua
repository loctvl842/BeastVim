--- Render hook of search mode: `render.build` has already drawn the rows of the
--- result tree exactly like the normal tree; this adds the query line while
--- typing, the count, the empty message and the matched letters.
local config = require("beast.libs.explorer.config")
local state = require("beast.libs.explorer.state")

local M = {}

---@param tree Beast.Explorer.SearchTree
---@param loading boolean
---@return string
local function count_text(tree, loading)
	local files = tree.count == 1 and "file" or "files"
	return string.format("%d%s %s%s", tree.count, tree.capped and "+" or "", files, loading and "…" or "")
end

---@param lines string[]
---@param hls {line:integer,col_s:integer,col_e:integer,group:string}[]
---@param badges {line:integer,chunks:{[1]:string,[2]:string?}[]}[]
---@param nodes Beast.Explorer.Node[]
function M.apply(lines, hls, badges, nodes)
	local ms, tree = state.mode_state, state.tree
	local pad = string.rep(" ", config.padding)

	-- While typing, line 1 is the prompt. The caret is a real character: the
	-- window draws a trailing space as "-" (listchars), so the line never ends in one.
	if ms.prompting then
		lines[1] = pad .. "/" .. (ms.query == "" and "" or " " .. ms.query) .. "▏"
		hls[1].col_e = #lines[1] -- the title highlight is always hls[1]
		if ms.query ~= "" then
			badges[#badges + 1] = { line = 0, chunks = { { count_text(tree, ms.loading), "BeastExplorerSearchCount" } } }
		end
	end

	if ms.query ~= "" and #nodes == 0 and not ms.loading then
		local msg = pad .. string.format('No files match "%s"', ms.query)
		lines[#lines + 1] = msg
		hls[#hls + 1] = { line = #lines - 1, col_s = 0, col_e = #msg, group = "BeastExplorerComment" }
	end

	-- A pending create/rename row shifts the rows below it; skip the letters meanwhile.
	if state.inline_prompt_spacer then
		return
	end

	-- The name is the tail of each row's text.
	for i, node in ipairs(nodes) do
		local offsets = tree.positions[node.path]
		if offsets then
			local name_s = #lines[i + 1] - #node.name
			for off in pairs(offsets) do
				hls[#hls + 1] = { line = i, col_s = name_s + off, col_e = name_s + off + 1, group = "BeastExplorerSearchMatch" }
			end
		end
	end
end

return M
