-- =========================================================================
-- Test: finder file rows (format.filename / buffers / live_grep_header) and the
-- fuzzy-match highlight mapping through `src` ranges
-- (docs/dev-specs/finder-continuous.md, Phase 1)
--
-- Run as: nvim --clean --headless -l tests/test-finder-format.lua
-- =========================================================================
local H = dofile("tests/helpers/finder.lua")
H.boot()
local t = H.runner()

local format = require("beast.libs.finder.format")
local match_hl = require("beast.libs.finder.match_hl")

--- Rendered text of a row.
local function text(parts)
	local out = {}
	for _, p in ipairs(parts) do
		out[#out + 1] = p.text
	end
	return table.concat(out)
end

local cwd = vim.fn.getcwd()

-- Rows ---------------------------------------------------------------------
local root = format.filename({ text = "init.lua", file = cwd .. "/init.lua", cwd = cwd })
t.ok("root file: base only, no dir", not text(root):find("  ", 1, true) and text(root):find("init.lua", 1, true))

local nested = format.filename({ text = "lua/beast/a.lua", file = cwd .. "/lua/beast/a.lua", cwd = cwd })
t.ok("nested file: name first, dim folder after", text(nested):find("a.lua  lua/beast", 1, true) ~= nil, text(nested))
local dir_part
for _, p in ipairs(nested) do
	if p.hl == "BeastFinderListDir" then
		dir_part = p
	end
end
t.ok("folder is dim and mapped to its source range", dir_part and dir_part.text == "lua/beast" and dir_part.src[1] == 1 and dir_part.src[2] == 9)

local long = "api-reference/beta/includes/snippets/csharp/file.md"
local trimmed = format.filename({ text = long, file = cwd .. "/" .. long, cwd = cwd }, 30)
t.ok("long folder is trimmed with an ellipsis", text(trimmed):find("…", 1, true) ~= nil, text(trimmed))
local trimmed_dir
for _, p in ipairs(trimmed) do
	if p.hl == "BeastFinderListDir" then
		trimmed_dir = p
	end
end
t.ok("a trimmed folder has no source range", trimmed_dir and trimmed_dir.src == nil)

local header = format.live_grep_header({ file = cwd .. "/lua/beast/a.lua", cwd = cwd })
t.eq("grep header is the same row", text(header), text(nested))

-- Buffers ------------------------------------------------------------------
local b = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(b, cwd .. "/zz_fmt_buf.lua")
local clean = format.buffers({ text = cwd .. "/zz_fmt_buf.lua", file = cwd .. "/zz_fmt_buf.lua", cwd = cwd, buf = b })
t.ok("buffer row has no [n] prefix", not text(clean):find("[" .. b .. "]", 1, true))
t.ok("clean buffer has no [+]", not text(clean):find("[+]", 1, true))
vim.api.nvim_buf_set_lines(b, 0, -1, false, { "x" })
local dirty = format.buffers({ text = cwd .. "/zz_fmt_buf.lua", file = cwd .. "/zz_fmt_buf.lua", cwd = cwd, buf = b })
t.ok("modified buffer ends with [+]", text(dirty):sub(-4) == " [+]", text(dirty))
local nameless = format.buffers({ text = "[No Name] 9", cwd = cwd, buf = vim.api.nvim_create_buf(true, false) })
t.eq("nameless buffer is plain", text(nameless), "[No Name]")

-- Highlight mapping --------------------------------------------------------
--- Columns drawn for `positions` (1-based indexes of item.text) on a rendered row.
local function columns(item, width)
	local item_row = vim.deepcopy(item)
	local list_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, { text(format.filename(item_row, width)) })
	match_hl.apply_list(list_buf, { item_row }, function(it)
		return format.filename(it, width)
	end, 1, 1, 1)
	return match_hl.list_ranges(list_buf)[0] or {}
end

local item = { text = "lua/beast/a.lua", file = cwd .. "/lua/beast/a.lua", cwd = cwd }
-- Row: "<icon> a.lua  lua/beast"; icon width depends on devicons, so compare with the row text.
local row = text(format.filename(item))
local base_col = row:find("a.lua", 1, true) - 1
local dir_col = row:find("lua/beast", 1, true) - 1

item.positions = { 11 } -- the "a" of a.lua
local r = columns(item)
t.ok("base match lands on the file name", r[1] and r[1][1] == base_col and r[1][2] == base_col + 1, vim.inspect(r))

item.positions = { 1, 2, 3 } -- "lua" in the folder
r = columns(item)
t.ok("folder match lands on the folder", r[1] and r[1][1] == dir_col and r[1][2] == dir_col + 3, vim.inspect(r))

item.positions = { 8, 9, 10, 11 } -- "st/a": folder end, dropped "/", base start
r = columns(item)
t.eq("a match across the boundary is two ranges", #r, 2)

item.positions = { 10 } -- the dropped "/"
t.eq("a match on the dropped slash draws nothing", #columns(item), 0)

local lt = { text = long, file = cwd .. "/" .. long, cwd = cwd, positions = { 20 } } -- inside the trimmed folder
t.eq("a match in a trimmed folder draws nothing", #columns(lt, 30), 0)

-- Buffers: the item text is absolute, positions index it
local abs = { text = cwd .. "/lua/a.lua", file = cwd .. "/lua/a.lua", cwd = cwd }
abs.positions = { #cwd + 2 + 4 } -- the "a" of a.lua inside the absolute text
local buf_list = vim.api.nvim_create_buf(false, true)
local function fmt(it)
	return format.buffers(it)
end
match_hl.apply_list(buf_list, { abs }, fmt, 1, 1, 1)
local abs_row = text(fmt(abs))
local abs_r = match_hl.list_ranges(buf_list)[0] or {}
t.ok("absolute item text maps through the cwd prefix", abs_r[1] and abs_r[1][1] == abs_row:find("a.lua", 1, true) - 1, vim.inspect(abs_r))

t.done()
