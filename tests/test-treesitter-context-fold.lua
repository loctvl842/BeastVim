-- ==============================================================================
-- Test: Treesitter context header honors closed folds
-- ==============================================================================
-- Run as: NVIM_APPNAME=BeastVim nvim --clean --headless -l tests/test-treesitter-context-fold.lua
-- Exit code: 0 = PASS, 1 = FAIL
--
-- A closed fold shows only its first row. The sticky context header must show
-- the same rows instead of expanding the folded parameters.
-- ==============================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
-- Installed parsers and context queries live under stdpath("data")/site
vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/site")
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

_G.View = require("beast.libs.view")
local context = require("beast.libs.treesitter.context.context")
local query_loader = require("beast.libs.treesitter.context.query")
local render = require("beast.libs.treesitter.context.render")

local passed = 0
local failed = 0
local skipped = 0

---@param name string
---@param got any
---@param expected any
local function assert_eq(name, got, expected)
	if vim.deep_equal(got, expected) then
		passed = passed + 1
		io.write(" PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write(" FAIL: " .. name .. "\n")
		io.write("   expected: " .. vim.inspect(expected) .. "\n")
		io.write("   got:      " .. vim.inspect(got) .. "\n")
	end
end

---Build a function whose header spans lines 1-4 and a body tall enough that
---the header scrolls out of view.
---@return string[]
local function function_lines()
	local lines = {
		"def f(",
		"    a,",
		"    b,",
		"):",
	}
	for i = 1, 40 do
		lines[#lines + 1] = "    x_" .. i .. " = " .. i
	end
	return lines
end

---Open `lines` in a scratch Python buffer and scroll to the last body line.
---@param lines string[]
---@param fold boolean close a fold over the header rows 1-3
---@return integer bufnr, integer winid
local function open(lines, fold)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_current_buf(buf)
	vim.treesitter.start(buf, "python")
	vim.wo.foldmethod = "manual"
	vim.wo.foldenable = true
	vim.wo.scrolloff = 0
	if fold then
		-- Close the parameter list, starting on the declaration line so the
		-- fold start matches the context header start.
		vim.cmd("1,3fold")
	end
	vim.cmd("normal! G")
	return buf, vim.api.nvim_get_current_win()
end

---@param lines string[]
local function strip_header(lines)
	local out = {}
	for _, line in ipairs(lines) do
		out[#out + 1] = line
	end
	return out
end

---@param ranges Range4[]
---@param lines string[]
---@return boolean
local function spans_match_lines(ranges, lines)
	local total = 0
	for _, range in ipairs(ranges) do
		total = total + (range[3] - range[1])
	end
	return total == #lines
end

if not pcall(vim.treesitter.get_string_parser, "", "python") then
	io.write("SKIP: python parser unavailable\n")
	os.exit(0)
end

if not query_loader.has("python") then
	skipped = skipped + 1
	io.write("SKIP: python context query unavailable\n")
	os.exit(0)
end

io.write("\n= Context header with a closed fold =\n")

do
	local buf, win = open(function_lines(), true)
	assert_eq("fold is closed over lines 1-3", {
		vim.fn.foldclosed(1),
		vim.fn.foldclosed(2),
		vim.fn.foldclosed(3),
		vim.fn.foldclosed(4),
	}, { 1, 1, 1, -1 })

	local ranges, lines = context.get(win)
	assert_eq("only visible header rows are shown", strip_header(lines), { "def f(", "):" })
	assert_eq("visible rows are split into contiguous segments", ranges, {
		{ 0, 0, 1, 0 },
		{ 3, 0, 4, 0 },
	})
	assert_eq("segment spans match their line counts", spans_match_lines(ranges, lines), true)

	-- Render and inspect the float: the fold row must carry Folded and no
	-- syntax highlight, mirroring the source window's closed fold line.
	vim.treesitter.get_parser(buf):parse()
	render.open(win, ranges, lines, true)
	local ctx_buf = nil
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.bo[b].filetype == "beast-treesitter-context" and vim.deep_equal(vim.api.nvim_buf_get_lines(b, 0, -1, false), lines) then
			ctx_buf = b
			break
		end
	end
	assert_eq("context float buffer exists", ctx_buf ~= nil, true)
	if ctx_buf then
		local ns = vim.api.nvim_get_namespaces()["beastvim_treesitter_context"]
		local folded_prio, syntax_marks = nil, 0
		for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(ctx_buf, ns, 0, -1, { details = true })) do
			if mark[2] == 0 then
				if mark[4].hl_group == "Folded" then
					folded_prio = mark[4].priority
				end
				local hl = mark[4].hl_group
				if type(hl) == "string" and hl:sub(1, 1) == "@" then
					syntax_marks = syntax_marks + 1
				end
			end
		end
		assert_eq("fold row is painted with Folded", folded_prio ~= nil, true)
		assert_eq("Folded stays below the syntax captures", folded_prio, 0)
		assert_eq("fold row keeps its syntax highlights", syntax_marks > 0, true)
	end

	render.close(win)
	vim.api.nvim_buf_delete(buf, { force = true })
end

io.write("\n= Context header with folds open (control) =\n")

do
	local buf, win = open(function_lines(), false)
	local ranges, lines = context.get(win)
	assert_eq("all header rows are shown", strip_header(lines), { "def f(", "    a,", "    b,", "):" })
	assert_eq("header stays a single segment", ranges, { { 0, 0, 4, 0 } })
	assert_eq("segment spans match their line counts", spans_match_lines(ranges, lines), true)
	vim.api.nvim_buf_delete(buf, { force = true })
end

io.write(string.format("\n%d passed, %d failed, %d skipped\n", passed, failed, skipped))
if failed > 0 then
	os.exit(1)
end
os.exit(0)
