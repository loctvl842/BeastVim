-- =========================================================================
-- Test: Tabline edge-trim truncation
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-tabline-edge-trim.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Stubs for globals (same as bench-tabline.lua)
_G.Theme = {
	get = function()
		return setmetatable({}, {
			__index = function()
				return "#ffffff"
			end,
		})
	end,
}
_G.Util = {
	colors = {
		set_hl = function() end,
		lighten = function()
			return "#ffffff"
		end,
		blend = function()
			return "#ffffff"
		end,
		inspect = function()
			return setmetatable({}, {
				__index = function()
					return nil
				end,
			})
		end,
	},
}
_G.Buffer = { delete = function() end }

-- =========================================================================
-- Test helpers
-- =========================================================================

local passed = 0
local failed = 0

local function assert_test(name, condition, msg)
	if condition then
		passed = passed + 1
		io.write("  PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL: " .. name .. " — " .. (msg or "assertion failed") .. "\n")
	end
end

--- Strip tabline highlight groups and click regions, returning visible text.
---@param tabline_str string
---@return string
local function strip_hl(tabline_str)
	local s = tabline_str
	-- Remove %@…@ click regions (non-greedy)
	s = s:gsub("%%%d+@[^@]+@", "")
	-- Remove %X (close click region)
	s = s:gsub("%%X", "")
	-- Remove %#…# highlight groups
	s = s:gsub("%%#[^#]+#", "")
	-- Remove %= (right-align)
	s = s:gsub("%%=", "")
	return s
end

-- =========================================================================
-- Setup
-- =========================================================================

local buffer_list = require("beast.libs.tabline.sections.buffer_list")
local config = require("beast.libs.tabline.config")
local truncate = require("beast.libs.tabline.truncate")

-- =========================================================================
-- Test: name.truncate_text_end
-- =========================================================================

io.write("\n--- name.truncate_text_end ---\n")
local name_mod = require("beast.libs.tabline.name")

assert_test("trailing ellipsis basic", name_mod.truncate_text_end("hello.lua", 5) == "hell…", "got: " .. name_mod.truncate_text_end("hello.lua", 5))
assert_test("trailing ellipsis fits", name_mod.truncate_text_end("hi", 5) == "hi", "got: " .. name_mod.truncate_text_end("hi", 5))
assert_test("trailing ellipsis max_width=1", name_mod.truncate_text_end("hello", 1) == "…", "got: " .. name_mod.truncate_text_end("hello", 1))
assert_test("trailing ellipsis max_width=0", name_mod.truncate_text_end("hello", 0) == "", "got: " .. name_mod.truncate_text_end("hello", 0))
assert_test("trailing ellipsis exact", name_mod.truncate_text_end("abc", 3) == "abc", "got: " .. name_mod.truncate_text_end("abc", 3))

-- =========================================================================
-- Test: leading ellipsis (existing function, sanity check)
-- =========================================================================

io.write("\n--- name.truncate_text ---\n")

assert_test("leading ellipsis basic", name_mod.truncate_text("hello.lua", 5) == "….lua", "got: " .. name_mod.truncate_text("hello.lua", 5))
assert_test("leading ellipsis fits", name_mod.truncate_text("hi", 5) == "hi", "got: " .. name_mod.truncate_text("hi", 5))

-- =========================================================================
-- Test: Edge-trim with min_cell_width — the bug scenario
-- =========================================================================

io.write("\n--- edge-trim with min_cell_width ---\n")

-- Open test buffers with known names
local test_files = {}
for i = 1, 12 do
	local fname = string.format("test_buf_%02d.lua", i)
	vim.cmd.edit(fname)
	table.insert(test_files, fname)
end

-- Set the active buffer to one in the middle
local listed = vim.tbl_filter(function(b)
	return vim.bo[b].buflisted
end, vim.api.nvim_list_bufs())
table.sort(listed)

-- Simulate: enough buffers to cause truncation
local function run_render_test(test_name, columns, min_cell_w)
	config.setup({ min_cell_width = min_cell_w })

	-- Build a mock-ish context by using the real context builder
	local context = require("beast.libs.tabline.context")
	local state = {
		last_active_bufnr = listed[math.ceil(#listed / 2)],
		last_diag_by_buf = nil,
	}
	local ctx = context.build(state)
	-- Override columns to simulate narrow terminal
	ctx.columns = columns
	ctx.tabpages_width = 0

	-- Simulate production devicons: inject a 1-display-col icon for each buffer
	for _, bufnr in ipairs(ctx.listed_buffers) do
		ctx.icons_by_buf[bufnr] = { icon = "*", color = "#51a0cf" }
	end

	local rendered, visible, left_hidden, right_hidden = buffer_list.render(ctx)

	-- Compute visible width of the rendered tabline (buffer list section only)
	local visible_text = strip_hl(rendered)
	local display_w = vim.fn.strdisplaywidth(visible_text)

	-- The buffer list portion must not exceed available width
	local available = columns - (ctx.sidebar_width or 0) - ctx.tabpages_width

	assert_test(
		test_name .. " (cols=" .. columns .. ", min_cell=" .. min_cell_w .. ")",
		display_w <= available,
		string.format("display_w=%d > available=%d (left=%d, right=%d, visible=%d)", display_w, available, left_hidden, right_hidden, #visible)
	)

	-- Waste should be minimal when truncation occurs
	-- Structural waste can be up to ~overhead (7-9) when the next cell can't fit
	if left_hidden > 0 or right_hidden > 0 then
		local waste = available - display_w
		assert_test(
			test_name .. " waste < cell overhead",
			waste < 12,
			string.format("waste=%d cols (left=%d, right=%d)", waste, left_hidden, right_hidden)
		)
	end

	return display_w, available, #visible, left_hidden, right_hidden
end

-- Test: min_cell_width=0 (default) — various widths
run_render_test("no min_cell_width, wide", 200, 0)
run_render_test("no min_cell_width, narrow", 80, 0)
run_render_test("no min_cell_width, very narrow", 40, 0)

-- Test: min_cell_width=18 — the bug scenario from the user report
run_render_test("min_cell_width=18, wide", 200, 18)
run_render_test("min_cell_width=18, medium", 181, 18)
run_render_test("min_cell_width=18, narrow", 120, 18)
run_render_test("min_cell_width=18, very narrow", 60, 18)

-- Test: min_cell_width larger than most cells
run_render_test("min_cell_width=25, medium", 150, 25)
run_render_test("min_cell_width=25, narrow", 80, 25)

-- Test: no truncation needed (wide enough for all)
run_render_test("no truncation needed", 500, 0)
run_render_test("no truncation needed with min_cell", 500, 18)

-- =========================================================================
-- Test: fit_around_anchor returns total_width
-- =========================================================================

io.write("\n--- fit_around_anchor total_width ---\n")

do
	config.setup({})
	local context = require("beast.libs.tabline.context")
	local state = { last_active_bufnr = listed[1], last_diag_by_buf = nil }
	local ctx = context.build(state)

	-- Simulate production devicons
	for _, bufnr in ipairs(ctx.listed_buffers) do
		ctx.icons_by_buf[bufnr] = { icon = "*", color = "#51a0cf" }
	end

	local function est_fn(bufnr, is_anchor)
		return truncate.estimate_cell_width(bufnr, ctx, is_anchor)
	end

	local visible, lh, rh, tw = truncate.fit_around_anchor({}, listed[1], vim.list_slice(listed, 2), est_fn, 500)

	assert_test("total_width is a number", type(tw) == "number", "got: " .. type(tw))
	assert_test("total_width > 0", tw > 0, "got: " .. tostring(tw))

	-- total_width should equal sum of estimated widths of visible buffers
	local sum = 0
	for i, bufnr in ipairs(visible) do
		sum = sum + est_fn(bufnr, i == 1 and bufnr == listed[1])
	end
	assert_test("total_width matches sum", tw == sum, string.format("tw=%d sum=%d", tw, sum))
end

-- =========================================================================
-- Test: Exact user scenario — 12 buffers, anchor near end, left-only truncation
-- =========================================================================

io.write("\n--- exact user scenario (left-only truncation, min_cell=18) ---\n")

do
	-- Clean up previous test buffers
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(b) and b ~= vim.api.nvim_get_current_buf() then
			pcall(vim.api.nvim_buf_delete, b, { force = true })
		end
	end

	-- Open the exact buffers from the user's report
	local user_files = {
		"lua/beast/libs/animate.lua",
		"lua/beast/libs/async.lua",
		"lua/beast/libs/buf.lua",
		"lua/beast/libs/view.lua",
		"lua/beast/icon.lua",
		"lua/beast/init.lua",
		"lua/beast/option.lua",
		"lua/beast/palette.lua",
		"lua/beast/profile.lua",
		"commit.lua",
		"init.lua",
		"nvim-pack-lock.json",
	}
	for _, f in ipairs(user_files) do
		pcall(vim.cmd.edit, f)
	end

	-- Get listed buffers
	local user_listed = vim.tbl_filter(function(b)
		return vim.bo[b].buflisted
	end, vim.api.nvim_list_bufs())
	table.sort(user_listed)

	-- Find commit.lua buffer (the anchor)
	local commit_buf = nil
	for _, b in ipairs(user_listed) do
		local name = vim.api.nvim_buf_get_name(b)
		if name:match("commit%.lua$") then
			commit_buf = b
			break
		end
	end

	config.setup({ min_cell_width = 18 })
	local context = require("beast.libs.tabline.context")
	local state_user = {
		last_active_bufnr = commit_buf,
		last_diag_by_buf = nil,
	}

	-- Make commit.lua the current buffer
	if commit_buf then
		pcall(vim.api.nvim_set_current_buf, commit_buf)
	end

	local ctx_user = context.build(state_user)
	ctx_user.columns = 181
	ctx_user.tabpages_width = 0

	-- Simulate production devicons
	for _, bufnr in ipairs(ctx_user.listed_buffers) do
		ctx_user.icons_by_buf[bufnr] = { icon = "*", color = "#51a0cf" }
	end

	local rendered_user, visible_user, lh_user, rh_user = buffer_list.render(ctx_user)
	local visible_text_user = strip_hl(rendered_user)
	local display_w_user = vim.fn.strdisplaywidth(visible_text_user)
	local available_user = 181 - (ctx_user.sidebar_width or 0) - ctx_user.tabpages_width

	assert_test(
		"user scenario: width <= available",
		display_w_user <= available_user,
		string.format("display_w=%d > available=%d", display_w_user, available_user)
	)

	-- Edge-trimmed cell should use the freed space — waste should be minimal
	local waste = available_user - display_w_user
	assert_test(
		"user scenario: waste < cell_overhead (no large gap)",
		waste < 10,
		string.format("waste=%d cols (left=%d, right=%d, visible=%d)", waste, lh_user, rh_user, #visible_user)
	)

	-- With 12 buffers and 181 cols, most should be visible
	assert_test(
		"user scenario: at least 9 buffers visible",
		#visible_user >= 9,
		string.format("only %d visible (left=%d, right=%d)", #visible_user, lh_user, rh_user)
	)
end

-- =========================================================================
-- Test: SKILL.md anchor — both-side truncation, right pull-in
-- =========================================================================

io.write("\n--- SKILL.md anchor (both-side truncation, min_cell=18) ---\n")

do
	-- Clean up previous test buffers
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(b) and b ~= vim.api.nvim_get_current_buf() then
			pcall(vim.api.nvim_buf_delete, b, { force = true })
		end
	end

	-- Open the exact buffers from the user's SKILL.md report
	local skillmd_files = {
		"commit.lua",
		"init.lua",
		"nvim-pack-lock.json",
		"sample_ui_finder",
		"SKILL.md",
		"stylua.toml",
		"lua/beast/icon.lua",
		"lua/beast/init.lua",
		"lua/beast/option.lua",
		"lua/beast/palette.lua",
		"lua/beast/profile.lua",
	}
	for _, f in ipairs(skillmd_files) do
		pcall(vim.cmd.edit, f)
	end

	-- Set SKILL.md as anchor
	local skill_buf = nil
	local skill_listed = vim.tbl_filter(function(b)
		return vim.bo[b].buflisted
	end, vim.api.nvim_list_bufs())
	table.sort(skill_listed)
	for _, b in ipairs(skill_listed) do
		if vim.api.nvim_buf_get_name(b):match("SKILL%.md$") then
			skill_buf = b
			break
		end
	end

	config.setup({ min_cell_width = 18 })
	local context = require("beast.libs.tabline.context")
	if skill_buf then
		pcall(vim.api.nvim_set_current_buf, skill_buf)
	end
	local ctx_skill = context.build({ last_active_bufnr = skill_buf, last_diag_by_buf = nil })
	ctx_skill.columns = 181
	ctx_skill.tabpages_width = 0

	-- Simulate production devicons: inject a 1-display-col icon for each buffer
	-- In production, nerd font icons (e.g. ) are 1 display col wide
	for _, bufnr in ipairs(ctx_skill.listed_buffers) do
		ctx_skill.icons_by_buf[bufnr] = { icon = "*", color = "#51a0cf" }
	end

	local rendered_skill, vis_skill, lh_skill, rh_skill = buffer_list.render(ctx_skill)
	local text_skill = strip_hl(rendered_skill)
	local dw_skill = vim.fn.strdisplaywidth(text_skill)
	local avail_skill = 181 - (ctx_skill.sidebar_width or 0) - ctx_skill.tabpages_width

	assert_test(
		"SKILL.md: width <= available",
		dw_skill <= avail_skill,
		string.format("display_w=%d > available=%d", dw_skill, avail_skill)
	)

	local waste_skill = avail_skill - dw_skill
	assert_test(
		"SKILL.md: waste < cell overhead",
		waste_skill < 8,
		string.format("waste=%d cols (left=%d, right=%d, visible=%d)", waste_skill, lh_skill, rh_skill, #vis_skill)
	)

	-- Should pull in an extra cell via Step G
	assert_test(
		"SKILL.md: at least 9 buffers visible",
		#vis_skill >= 9,
		string.format("only %d visible (left=%d, right=%d)", #vis_skill, lh_skill, rh_skill)
	)
end

-- =========================================================================
-- Test: commit.lua selected first, right-only truncation with pull-in
-- =========================================================================

io.write("\n--- commit.lua selected first, right-only truncation ---\n")

do
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(b) and b ~= vim.api.nvim_get_current_buf() then
			pcall(vim.api.nvim_buf_delete, b, { force = true })
		end
	end

	local first_files = {
		"commit.lua",
		"init.lua",
		"nvim-pack-lock.json",
		"sample_ui_finder",
		"SKILL.md",
		"stylua.toml",
		"lua/beast/icon.lua",
		"lua/beast/init.lua",
		"lua/beast/option.lua",
		"lua/beast/palette.lua",
		"lua/beast/profile.lua",
		"lua/beast/libs/animate.lua",
		"lua/beast/libs/async.lua",
		"lua/beast/libs/buf.lua",
		"lua/beast/libs/view.lua",
	}
	for _, f in ipairs(first_files) do
		pcall(vim.cmd.edit, f)
	end

	local first_listed = vim.tbl_filter(function(b)
		return vim.bo[b].buflisted
	end, vim.api.nvim_list_bufs())
	table.sort(first_listed)

	local first_commit_buf
	for _, b in ipairs(first_listed) do
		if vim.api.nvim_buf_get_name(b):match("commit%.lua$") then
			first_commit_buf = b
			break
		end
	end

	config.setup({ min_cell_width = 18 })
	local context = require("beast.libs.tabline.context")
	if first_commit_buf then
		pcall(vim.api.nvim_set_current_buf, first_commit_buf)
	end
	local ctx_first = context.build({ last_active_bufnr = first_commit_buf, last_diag_by_buf = nil })
	ctx_first.columns = 181
	ctx_first.tabpages_width = 0
	for _, bufnr in ipairs(ctx_first.listed_buffers) do
		ctx_first.icons_by_buf[bufnr] = { icon = "*", color = "#51a0cf" }
	end

	local r_first, v_first, lh_first, rh_first = buffer_list.render(ctx_first)
	local t_first = strip_hl(r_first)
	local dw_first = vim.fn.strdisplaywidth(t_first)
	local avail_first = 181 - (ctx_first.sidebar_width or 0) - ctx_first.tabpages_width

	assert_test(
		"commit first: width <= available",
		dw_first <= avail_first,
		string.format("display_w=%d > available=%d", dw_first, avail_first)
	)

	local waste_first = avail_first - dw_first
	assert_test(
		"commit first: waste < cell overhead",
		waste_first < 8,
		string.format("waste=%d cols (left=%d, right=%d, visible=%d)", waste_first, lh_first, rh_first, #v_first)
	)

	-- commit.lua is first so no left hidden
	assert_test(
		"commit first: no left truncation",
		lh_first == 0,
		string.format("left_hidden=%d expected 0", lh_first)
	)
end

-- =========================================================================
-- Test: sample_ui_finder anchor with explorer sidebar, both-side truncation
-- =========================================================================

io.write("\n--- sample_ui_finder with explorer sidebar ---\n")

do
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(b) and b ~= vim.api.nvim_get_current_buf() then
			pcall(vim.api.nvim_buf_delete, b, { force = true })
		end
	end

	local sidebar_files = {
		"commit.lua",
		"init.lua",
		"nvim-pack-lock.json",
		"sample_ui_finder",
		"SKILL.md",
		"stylua.toml",
		"lua/beast/icon.lua",
		"lua/beast/init.lua",
		"lua/beast/option.lua",
		"lua/beast/palette.lua",
		"lua/beast/profile.lua",
	}
	for _, f in ipairs(sidebar_files) do
		pcall(vim.cmd.edit, f)
	end

	local sb_listed = vim.tbl_filter(function(b)
		return vim.bo[b].buflisted
	end, vim.api.nvim_list_bufs())
	table.sort(sb_listed)

	local sb_anchor_buf
	for _, b in ipairs(sb_listed) do
		if vim.api.nvim_buf_get_name(b):match("sample_ui_finder$") then
			sb_anchor_buf = b
			break
		end
	end

	config.setup({ min_cell_width = 18 })
	local context = require("beast.libs.tabline.context")
	if sb_anchor_buf then
		pcall(vim.api.nvim_set_current_buf, sb_anchor_buf)
	end
	local ctx_sb = context.build({ last_active_bufnr = sb_anchor_buf, last_diag_by_buf = nil })
	ctx_sb.columns = 181
	ctx_sb.tabpages_width = 0
	ctx_sb.sidebar_width = 40 -- Explorer sidebar
	for _, bufnr in ipairs(ctx_sb.listed_buffers) do
		ctx_sb.icons_by_buf[bufnr] = { icon = "*", color = "#51a0cf" }
	end

	local r_sb, v_sb, lh_sb, rh_sb = buffer_list.render(ctx_sb)
	local t_sb = strip_hl(r_sb)
	local dw_sb = vim.fn.strdisplaywidth(t_sb)
	local avail_sb = 181 - 40 - ctx_sb.tabpages_width

	assert_test(
		"sidebar: width <= available",
		dw_sb <= avail_sb,
		string.format("display_w=%d > available=%d", dw_sb, avail_sb)
	)

	local waste_sb = avail_sb - dw_sb
	assert_test(
		"sidebar: waste < compact overhead (tight fill)",
		waste_sb < 4,
		string.format("waste=%d cols (left=%d, right=%d, visible=%d)", waste_sb, lh_sb, rh_sb, #v_sb)
	)

	-- With 11 buffers and 141 available, should show at least 7 (6 full + 1 compact pull-in)
	assert_test(
		"sidebar: at least 7 buffers visible",
		#v_sb >= 7,
		string.format("only %d visible (left=%d, right=%d)", #v_sb, lh_sb, rh_sb)
	)
end

-- =========================================================================
-- Test: beast/init.lua anchor, sidebar, left-only truncation, left pull-in
-- =========================================================================

io.write("\n--- beast/init.lua anchor, sidebar, left-only truncation ---\n")

do
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(b) and b ~= vim.api.nvim_get_current_buf() then
			pcall(vim.api.nvim_buf_delete, b, { force = true })
		end
	end

	local left_files = {
		"commit.lua",
		"init.lua",
		"nvim-pack-lock.json",
		"sample_ui_finder",
		"SKILL.md",
		"stylua.toml",
		"lua/beast/icon.lua",
		"lua/beast/init.lua",
		"lua/beast/option.lua",
		"lua/beast/palette.lua",
		"lua/beast/profile.lua",
	}
	for _, f in ipairs(left_files) do
		pcall(vim.cmd.edit, f)
	end

	local left_listed = vim.tbl_filter(function(b)
		return vim.bo[b].buflisted
	end, vim.api.nvim_list_bufs())
	table.sort(left_listed)

	-- beast/init.lua is the anchor
	local left_anchor_buf
	for _, b in ipairs(left_listed) do
		local name = vim.api.nvim_buf_get_name(b)
		if name:match("lua/beast/init%.lua$") then
			left_anchor_buf = b
			break
		end
	end

	config.setup({ min_cell_width = 18 })
	local context = require("beast.libs.tabline.context")
	if left_anchor_buf then
		pcall(vim.api.nvim_set_current_buf, left_anchor_buf)
	end
	local ctx_left = context.build({ last_active_bufnr = left_anchor_buf, last_diag_by_buf = nil })
	ctx_left.columns = 181
	ctx_left.tabpages_width = 0
	ctx_left.sidebar_width = 40
	for _, bufnr in ipairs(ctx_left.listed_buffers) do
		ctx_left.icons_by_buf[bufnr] = { icon = "*", color = "#51a0cf" }
	end

	local r_left, v_left, lh_left, rh_left = buffer_list.render(ctx_left)
	local t_left = strip_hl(r_left)
	local dw_left = vim.fn.strdisplaywidth(t_left)
	local avail_left = 181 - 40 - ctx_left.tabpages_width

	assert_test(
		"left pull-in: width <= available",
		dw_left <= avail_left,
		string.format("display_w=%d > available=%d", dw_left, avail_left)
	)

	local waste_left = avail_left - dw_left
	assert_test(
		"left pull-in: waste < compact overhead",
		waste_left < 5,
		string.format("waste=%d cols (left=%d, right=%d, visible=%d)", waste_left, lh_left, rh_left, #v_left)
	)

	-- Right side has no hidden (profile.lua is last), all hidden are on left
	assert_test(
		"left pull-in: no right truncation",
		rh_left == 0,
		string.format("right_hidden=%d expected 0", rh_left)
	)

	-- Should pull in one buffer on the left side via compact
	assert_test(
		"left pull-in: at least 8 buffers visible",
		#v_left >= 8,
		string.format("only %d visible (left=%d, right=%d)", #v_left, lh_left, rh_left)
	)
end

-- =========================================================================
-- Summary
-- =========================================================================

io.write(string.format("\n=== %d passed, %d failed ===\n", passed, failed))
if failed > 0 then
	os.exit(1)
else
	os.exit(0)
end
