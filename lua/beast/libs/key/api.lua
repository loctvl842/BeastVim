local core = require("beast.libs.key.core")

---@class Beast.Key.API.Segment
---@field text string
---@field hl? string

---@alias Beast.Key.API.Line Beast.Key.API.Segment[]

---@class Beast.Key.API.Entry
---@field source string
---@field mode string
---@field lhs string
---@field rhs string
---@field desc? string
---@field group? string
---@field buffer? integer
---@field callback? function
---@field src? string -- cached resolved source info for display (e.g. file:line)

-- filters/state
---@type boolean
local beast_only = true
---@type string
local filter_mode = "all" -- one of: all | n|v|i|x|s|o|c|t
---@type string[]
local mode_order = { "n", "v", "i", "x", "s", "o", "c", "t" }
---@type table<string, boolean>
local expanded = {} -- map id (lhs) -> true when showing source
---@type table<integer, string>?
local script_map -- lazily populated map: sid -> script path
---@type integer?
local target_buf -- buffer whose local keymaps we display (the editor buffer active before opening UI)
---@type Beast.Key.API.Entry[]?
local nvim_maps_cache

local M = {}

---@generic T : table
---@param list T[]
---@param field string
---@return T[]
local function normalize_length(list, field)
  -- stylua: ignore start
  local max_len = 0
  for _, a in ipairs(list) do max_len = math.max(max_len, #a[field]) end
  for _, a in ipairs(list) do a[field] = a[field] .. string.rep(" ", max_len - #a[field]) end
  return list
end

---@return table<integer, string>
local function get_script_map()
  --stylua: ignore
  if script_map then return script_map end
	script_map = {}
	local ok, out = pcall(vim.api.nvim_exec2, "scriptnames", { output = true })
	if ok and out and out.output then
		for line in out.output:gmatch("[^\n]+") do
			-- lines look like: " 42: /path/to/file.lua"
			local sid, path = line:match("^%s*(%d+):%s+(.+)$")
      --stylua: ignore
      if sid and path then script_map[tonumber(sid)] = path end
		end
	end
	return script_map
end

---@param mode string
---@param lhs string
---@param cb? function
---@return string?
local function get_map_source(mode, lhs, cb)
	local file, lnum
	local ok, arg = pcall(vim.fn.maparg, lhs, mode, false, true)
	if ok and type(arg) == "table" and next(arg) ~= nil then
		if type(arg.sid) == "number" and arg.sid > 0 then
			local m = get_script_map()
			file = m[arg.sid]
		end
    --stylua: ignore
    if type(arg.lnum) == "number" then lnum = arg.lnum end
	end
	if (not file) and type(cb) == "function" then
		local info = debug.getinfo(cb, "S")
		if info and type(info.source) == "string" then
			if info.source:sub(1, 1) == "@" then
				file = info.source:sub(2)
				lnum = info.linedefined or lnum
			else
				file = info.short_src or info.source
			end
		end
	end
	if file then
		local disp = vim.fn.fnamemodify(file, ":~")
    --stylua: ignore
    if lnum then disp = string.format("%s:%d", disp, lnum) end
		return disp
	end
	return nil
end
---@param e Beast.Key.API.Entry
---@return string?
local function resolve_entry_source(e)
	if e.src then
		return e.src
	end
	e.src = get_map_source(e.mode, e.lhs, e.callback)
	return e.src
end

---@param rhs string|function|boolean|nil
---@return string
local function rhs_to_string(rhs)
  --stylua: ignore start
  if type(rhs) == "string" then return rhs end
  if type(rhs) == "function" then return "<fn>" end
  if rhs == false then return "<del>" end
  if rhs == nil then return "" end
  return tostring(rhs)
end

local function collect_beast_managed()
	local list = {}
	for _, km in pairs(core.managed) do
		table.insert(list, {
			source = "Beast",
			mode = km.mode,
			lhs = km.lhs,
			rhs = rhs_to_string(km.rhs),
			desc = km.desc,
			group = km.group,
			buffer = nil,
		})
	end
	return list
end

---@param lhs string
---@return string
local function normalize_lhs(lhs)
	lhs = lhs or ""
	-- Prefer raw leader tokens if present
	lhs = lhs:gsub("<Leader>", "<leader>")
	-- If leader is space and we see <Space>, show <leader>
	if (vim.g.mapleader == " " or vim.g.mapleader == "<Space>") and lhs:find("^<Space>") then
		lhs = lhs:gsub("^<Space>", "<leader>")
	end
	-- If lhs begins with the concrete leader character(s), re-canonicalize
	local ml = vim.g.mapleader
	if type(ml) == "string" and #ml > 0 and not lhs:match("^<") and lhs:sub(1, #ml) == ml then
		lhs = "<leader>" .. lhs:sub(#ml + 1)
	end
	return lhs
end

---@return Beast.Key.API.Entry[]
local function collect_nvim_maps()
	if nvim_maps_cache then
		return nvim_maps_cache
	end
	local modes = mode_order
	local list = {}
	for _, m in ipairs(modes) do
		local global = vim.api.nvim_get_keymap(m)
		for _, it in ipairs(global) do
			local lhs = normalize_lhs(it.lhs)
			table.insert(list, {
				source = "NVIM",
				mode = m,
				lhs = lhs,
				rhs = it.rhs or rhs_to_string(it.callback),
				desc = it.desc,
				buffer = nil,
				callback = it.callback,
			})
		end
		local buf = target_buf or 0
		local buf_local = vim.api.nvim_buf_get_keymap(buf, m)
		for _, it in ipairs(buf_local) do
			local lhs = normalize_lhs(it.lhs)
			table.insert(list, {
				source = "BUF",
				mode = m,
				lhs = lhs,
				rhs = it.rhs or rhs_to_string(it.callback),
				desc = it.desc,
				buffer = buf,
				callback = it.callback,
			})
		end
	end
	nvim_maps_cache = list
	return list
end

---@return Beast.Key.API.Entry[]
local function filtered_entries()
	local entries = {}
	if beast_only then
		entries = collect_beast_managed()
	else
		entries = collect_nvim_maps()
	end
	-- annotate managed ones for visibility
	local managed = {}
	for _, km in pairs(core.managed) do
		managed[(km.mode or "n") .. "\t" .. km.lhs] = true
	end
	for _, e in ipairs(entries) do
		if managed[e.mode .. "\t" .. e.lhs] and e.source ~= "BUF" then
			e.source = "Beast"
		end
	end

	-- filter by mode
	if filter_mode ~= "all" then
		local out = {}
		for _, e in ipairs(entries) do
			if e.mode == filter_mode then
				table.insert(out, e)
			end
		end
		entries = out
	end

	table.sort(entries, function(a, b)
		if a.mode == b.mode then
			if a.lhs == b.lhs then
				return (a.source or "") < (b.source or "")
			end
			return a.lhs < b.lhs
		end
		local ai, bi = 9, 9
		for i, m in ipairs(mode_order) do
			if m == a.mode then
				ai = i
			end
			if m == b.mode then
				bi = i
			end
		end
		return ai < bi
	end)
	return entries
end

---@param entries Beast.Key.API.Entry[]
---@return Beast.Key.API.Line[]
local function build_content_lines(entries)
	local lines = {}
	local title = "  🦁 Keymaps"
	table.insert(lines, { { text = title, hl = "BeastKeyTitle" } })
	local mlabel = filter_mode == "all" and "All" or filter_mode
	local blabel = beast_only and "Beast" or "All"
	local stats = string.format("  Mode: %s   Source: %s", mlabel, blabel)

	table.insert(lines, { { text = stats, hl = "BeastKeyComment" } })
	table.insert(lines, { { text = "", hl = nil } })

	if #entries == 0 then
		table.insert(lines, { { text = "  (no keymaps)", hl = "BeastKeyComment" } })
		return lines
	end

	-- Group entries by their group name
	local by_group = {}
	local group_order = {}
	for _, e in ipairs(entries) do
		local gname = (e.group and #e.group > 0) and e.group or "Ungrouped"
		if not by_group[gname] then
			by_group[gname] = {}
			table.insert(group_order, gname)
		end
		table.insert(by_group[gname], e)
	end

    -- stylua: ignore
    table.sort(group_order, function(a, b)
      if a == "Ungrouped" then return false end
      if b == "Ungrouped" then return true end
      return a:lower() < b:lower()
    end)
	for _, gname in ipairs(group_order) do
		local show_header = gname ~= "Ungrouped"
      -- stylua: ignore
      if show_header then table.insert(lines, { { text = "  " .. gname, hl = "BeastKeyH2" } }) end

		-- Within group, collapse duplicates by lhs and aggregate modes
		local groups = {}
		local order = {}
		for _, e in ipairs(by_group[gname]) do
			local id = (e.lhs or "")
			if not groups[id] then
				groups[id] = { lhs = e.lhs, items = {}, modes = {} }
				table.insert(order, id)
			end
			table.insert(groups[id].items, e)
			if e.mode then
				groups[id].modes[e.mode] = true
			end
		end

		-- Pre-compute mode labels and primary items
		local prefix = show_header and "    " or "  "
		local computed = {}
		for _, id in ipairs(order) do
			local g = groups[id]
			local mode_label = ""
			for _, m in ipairs(mode_order) do
				if g.modes[m] then
					mode_label = mode_label .. m
				end
			end
			if mode_label == "" then
				mode_label = "?"
			end
			local primary = g.items[1]
			for _, it in ipairs(g.items) do
				if it.desc and #it.desc > 0 then
					primary = it
					break
				end
			end
			table.insert(computed, { id = id, g = g, mode_label = mode_label, lhs = g.lhs or "", primary = primary })
		end

		-- Pad mode and lhs columns for alignment
		normalize_length(computed, "mode_label")
		normalize_length(computed, "lhs")

		-- Build rows
		for _, c in ipairs(computed) do
			local row = {}
			table.insert(row, { text = prefix .. string.format("[%s] ", c.mode_label), hl = "BeastKeyKeys" })
			table.insert(row, { text = c.lhs, hl = nil })
			if c.primary.desc and #c.primary.desc > 0 then
				table.insert(row, { text = "  - ", hl = "BeastKeyComment" })
				table.insert(row, { text = c.primary.desc, hl = "BeastKeyComment" })
			end
			if #c.g.items > 1 then
				table.insert(row, { text = string.format("  ×%d", #c.g.items), hl = "BeastKeyComment" })
			end
			if expanded[c.id] and #c.g.items == 1 then
				local src = resolve_entry_source(c.primary)
				if src and #src > 0 then
					table.insert(row, { text = "  (", hl = "BeastKeyComment" })
					table.insert(row, { text = src, hl = "BeastKeyComment" })
					table.insert(row, { text = ")", hl = "BeastKeyComment" })
				end
			end
			table.insert(lines, row)

			if expanded[c.id] and #c.g.items > 1 then
				for _, it in ipairs(c.g.items) do
					local child = {}
					table.insert(child, { text = prefix .. "  • ", hl = "BeastKeyComment" })
					local label = (it.desc and #it.desc > 0) and it.desc or "(no description)"
					table.insert(child, { text = label, hl = "BeastKeyComment" })
					local src = resolve_entry_source(it)
					if src and #src > 0 then
						table.insert(child, { text = "  (", hl = "BeastKeyComment" })
						table.insert(child, { text = src, hl = "BeastKeyComment" })
						table.insert(child, { text = ")", hl = "BeastKeyComment" })
					end
					table.insert(lines, child)
				end
			end
		end
	end
	return lines
end

---@param id string
---@return Beast.Key.API.Line[]
function M.toggle_expand(id)
	expanded[id] = not expanded[id] or nil
	return build_content_lines(filtered_entries())
end

function M.cycle_mode()
	if filter_mode == "all" then
		filter_mode = mode_order[1]
	else
		local idx
		for i, m in ipairs(mode_order) do
			if m == filter_mode then
				idx = i
				break
			end
		end
		if idx and idx < #mode_order then
			filter_mode = mode_order[idx + 1]
		else
			filter_mode = "all"
		end
	end
	return build_content_lines(filtered_entries())
end

function M.toggle_beast_only()
	beast_only = not beast_only
	return build_content_lines(filtered_entries())
end

function M.default()
	return build_content_lines(filtered_entries())
end

return M
