local config = require("beast.libs.starter.config")

local M = {}

---@type Beast.Lib.Meta
M.meta = { name = "starter", description = "Dashboard / start screen" }

local ns = vim.api.nvim_create_namespace("BeastStarter")
local augroup ---@type integer|nil

-- Track the buffer + extmark so we can clear the overlay when the buffer
-- becomes non-empty (mirrors `may_show_intro()`'s screen-redraw behavior).
local active_buf ---@type integer|nil
local active_mark ---@type integer|nil

---@class Beast.Starter.Line
---@field text string
---@field kind "logo"|"version"|"sep"|"help"|"key"|"plain"|"blank"

---@alias Beast.Starter.Chunk [string, string?]

---Build the line list. Strings (and trailing whitespace) match the C
---`intro_message()` array in `src/nvim/version.c` so per-line centering
---reproduces the native vertical alignment.
---@return Beast.Starter.Line[]
local function build_lines()
	local v = vim.version()
	local version_str = string.format("NVIM v%d.%d.%d", v.major, v.minor, v.patch)
	if v.prerelease then
		version_str = version_str .. "-dev"
	end
	local news = string.format("type  :help news<Enter>     for v%d.%d notes ", v.major, v.minor)
	local sep = "─" -- sentinel; render() extends it to the table width

	local lines = {
		{ text = "│ ╲ ││", kind = "logo" },
		{ text = "││╲╲││", kind = "logo" },
		{ text = "││ ╲ │", kind = "logo" },
		{ text = "", kind = "blank" },
		{ text = version_str, kind = "version" },
		{ text = sep, kind = "sep" },
		{ text = "Nvim is open source and freely distributable", kind = "plain" },
		{ text = "https://neovim.io/#chat", kind = "plain" },
		{ text = sep, kind = "sep" },
		{ text = "type  :help nvim<Enter>     if you are new! ", kind = "help" },
		{ text = "type  :checkhealth<Enter>   to optimize Nvim", kind = "help" },
		{ text = "type  :q<Enter>             to exit         ", kind = "help" },
		{ text = "type  :help<Enter>          for help        ", kind = "help" },
		{ text = sep, kind = "sep" },
		{ text = news, kind = "help" },
	}

	-- BeastVim key rows are appended as their own table block. When `keys`
	-- is empty the section is skipped and the layout matches the native intro.
	local keys = config.keys or {}
	if #keys > 0 then
		table.insert(lines, { text = sep, kind = "sep" })
		local DESC_COL = 28
		for _, k in ipairs(keys) do
			local prefix = k.verb .. " " .. k.key
			local pad = math.max(1, DESC_COL - #prefix)
			table.insert(lines, { text = prefix .. string.rep(" ", pad) .. k.desc, kind = "key" })
		end
	end

	table.insert(lines, { text = sep, kind = "sep" })
	table.insert(lines, { text = "Help poor children in Uganda!", kind = "plain" })
	table.insert(lines, { text = "type  :help Kuwasha<Enter>  for information ", kind = "help" })

	return lines
end

-- Chunk builders (return virt_lines-compatible chunk arrays). Each chunk is
-- `{ text, hl_group }`. Multi-segment lines are tokenised by walking bytes,
-- matching `do_intro_line()` in `src/nvim/version.c`.

---@param text string
---@return Beast.Starter.Chunk[]
local function chunks_logo(text)
	-- "╲" diagonal: everything before is Special, everything from "╲" onward
	-- is String — matches the native two-tone logo coloring.
	local diag_byte = text:find("╲", 1, true)
	if not diag_byte then
		return { { text, "Special" } }
	end
	local out = {}
	if diag_byte > 1 then
		out[#out + 1] = { text:sub(1, diag_byte - 1), "Special" }
	end
	out[#out + 1] = { text:sub(diag_byte), "String" }
	return out
end

---@param text string
---@return Beast.Starter.Chunk[]
local function chunks_help(text)
	local out = {}
	local i, n = 1, #text
	local pending_start = 1
	local function flush(upto)
		if upto > pending_start then
			out[#out + 1] = { text:sub(pending_start, upto - 1) }
		end
		pending_start = upto
	end
	while i <= n do
		local ch = text:byte(i)
		if ch == 0x3C then -- '<'
			local close = text:find(">", i + 1, true) or n
			flush(i)
			out[#out + 1] = { text:sub(i, close), "SpecialKey" }
			i = close + 1
			pending_start = i
		elseif ch == 0x3A then -- ':'
			flush(i)
			out[#out + 1] = { ":", "SpecialKey" }
			-- Native (`do_intro_line` in version.c): the command segment
			-- runs from after ':' until the next '<' — so "help nvim" all
			-- gets Identifier, not just "help".
			local j = i + 1
			while j <= n and text:byte(j) ~= 0x3C do
				j = j + 1
			end
			if j > i + 1 then
				out[#out + 1] = { text:sub(i + 1, j - 1), "Identifier" }
			end
			i = j
			pending_start = i
		else
			i = i + 1
		end
	end
	flush(n + 1)
	return out
end

---@param text string
---@return Beast.Starter.Chunk[]
local function chunks_key(text)
	local out = {}
	local i, n = 1, #text
	local pending_start = 1
	local function flush(upto)
		if upto > pending_start then
			out[#out + 1] = { text:sub(pending_start, upto - 1) }
		end
		pending_start = upto
	end
	while i <= n do
		if text:byte(i) == 0x3C then -- '<'
			local close = text:find(">", i + 1, true)
			if not close then
				break
			end
			local seg_end = close
			while seg_end < n and text:byte(seg_end + 1) ~= 0x20 do
				seg_end = seg_end + 1
			end
			flush(i)
			out[#out + 1] = { text:sub(i, seg_end), "SpecialKey" }
			i = seg_end + 1
			pending_start = i
		else
			i = i + 1
		end
	end
	flush(n + 1)
	return out
end

---@param l Beast.Starter.Line
---@return Beast.Starter.Chunk[]
local function chunks_for(l)
	if l.kind == "logo" then
		return chunks_logo(l.text)
	elseif l.kind == "version" then
		return { { l.text, "String" } }
	elseif l.kind == "sep" then
		return { { l.text, "NonText" } }
	elseif l.kind == "help" then
		return chunks_help(l.text)
	elseif l.kind == "key" then
		return chunks_key(l.text)
	end
	return { { l.text } }
end

---@param buf integer
local function should_keep(buf)
	if not (buf and vim.api.nvim_buf_is_valid(buf)) then
		return false
	end
	if vim.api.nvim_buf_get_name(buf) ~= "" then
		return false
	end
	if vim.api.nvim_buf_line_count(buf) > 1 then
		return false
	end
	if (vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1] or "") ~= "" then
		return false
	end
	if vim.bo[buf].buftype ~= "" then
		return false
	end
	return true
end

---Remove the on-screen overlay but keep our autocmds alive so a later
---resize / redraw can re-render. Use `dispose()` for permanent teardown.
local function clear_overlay()
	if active_buf and active_mark and vim.api.nvim_buf_is_valid(active_buf) then
		pcall(vim.api.nvim_buf_del_extmark, active_buf, ns, active_mark)
	end
	active_mark = nil
end

---Permanent teardown: drop the overlay AND the augroup. Called when the
---starter is definitively no longer applicable (text typed, file loaded,
---different buffer shown, split opened, etc.) — mirrors native intro's
---one-shot lifecycle.
local function dispose()
	clear_overlay()
	active_buf = nil
	if augroup then
		pcall(vim.api.nvim_del_augroup_by_id, augroup)
		augroup = nil
	end
end

-- Back-compat alias for sites that previously called clear().
local clear = dispose

---Render the intro as virt_lines anchored at row 0 of `buf`. The buffer is
---NOT modified — virt_lines live in the grid only, so the cursor, line
---numbers, `modifiable`, and every other window/buffer setting behave exactly
---as the user has them configured. Vanishes as soon as the buffer becomes
---non-empty (`TextChanged*` autocmd → `clear()`).
---@param buf integer
local function render(buf)
	if not should_keep(buf) then
		dispose()
		return
	end

	local lines = build_lines()
	local win = vim.api.nvim_get_current_win()
	local win_info = vim.fn.getwininfo(win)[1] or {}
	-- `virt_lines` render starting at column `textoff` (after the
	-- number/sign/fold gutter). The native intro is painted directly onto
	-- the screen grid using `(Columns - width) / 2`, so to match that
	-- full-window centering we subtract textoff from the left padding —
	-- the resulting screen column is `textoff + left_pad = (cols - width)/2`.
	local textoff = win_info.textoff or 0
	local cols = vim.o.columns
	-- Use the window's actual height (excludes tabline / statusline / cmdline)
	-- so vertical centering doesn't drift down when a tabline is shown.
	local rows = vim.api.nvim_win_get_height(win)

	---@param width integer
	---@return integer
	local function center_pad(width)
		return math.max(0, math.floor((cols - width) / 2) - textoff)
	end

	-- The table (separators + help + key rows) all share one centered width
	-- based on the widest content line. The sep is a single "─" placeholder
	-- that gets extended here to fill that width.
	local table_width = 0
	for _, l in ipairs(lines) do
		if l.kind == "help" or l.kind == "key" then
			table_width = math.max(table_width, vim.fn.strdisplaywidth(l.text))
		end
	end
	local wide_sep = string.rep("─", table_width)
	for _, l in ipairs(lines) do
		if l.kind == "sep" then
			l.text = wide_sep
		end
	end
	local table_left = center_pad(table_width)

	-- Vertical layout based on actual content vs. screen height.
	-- Slot budget: `rows` screen lines total. The buffer's single empty
	-- line takes row 1; remaining `rows - 1` are virt_line slots below it.
	-- When content overflows by exactly one slot we also overlay the
	-- buffer's row 0 (using `virt_text_pos = "overlay"`) so its blank
	-- becomes the first content line — gaining one extra row before we
	-- give up. Anything larger than `rows` lines: don't render.
	local content_h = #lines
	if content_h > rows then
		clear_overlay()
		return
	end

	local use_overlay = content_h > (rows - 1)
	local available = use_overlay and rows or (rows - 1)
	-- Center vertically. The buffer's empty row 0 already contributes ONE
	-- row of visual top padding, so the blank virt_lines we add on top
	-- count as `top_pad + 1` visually. Bias toward the top means visual
	-- top <= visual bottom:
	--   visual_top    = top_pad + 1
	--   visual_bottom = leftover - top_pad
	-- => top_pad <= (leftover - 1) / 2
	-- e.g. leftover=5 → top_pad=2 (visual 3 / 3); leftover=4 → top_pad=1
	-- (visual 2 / 3); leftover=3 → top_pad=1 (visual 2 / 2). When using
	-- the overlay path (no empty row 0), use the symmetric floor instead.
	local leftover = available - content_h
	local top_pad
	if use_overlay then
		top_pad = math.floor(leftover / 2)
	else
		top_pad = math.max(0, math.floor((leftover - 1) / 2))
	end

	---@param l Beast.Starter.Line
	---@return Beast.Starter.Chunk[]
	local function build_row(l)
		local left
		if l.kind == "help" or l.kind == "key" or l.kind == "sep" then
			left = table_left
		else
			left = center_pad(vim.fn.strdisplaywidth(l.text))
		end
		local row_chunks = chunks_for(l)
		if left > 0 then
			table.insert(row_chunks, 1, { string.rep(" ", left) })
		end
		return row_chunks
	end

	-- When `use_overlay` is true, the first content line is painted on top
	-- of buffer row 0 via `virt_text`; the rest go as virt_lines below.
	-- When false, everything goes into virt_lines.
	local overlay_chunks
	local virt_lines = {}
	local consumed = 0
	for _ = 1, top_pad do
		if use_overlay and overlay_chunks == nil then
			-- First slot in overlay mode is the buffer row itself; a blank
			-- there is naturally rendered by the empty buffer line.
			overlay_chunks = false -- sentinel: blank-overlay (no virt_text)
		else
			virt_lines[#virt_lines + 1] = {}
		end
		consumed = consumed + 1
	end
	for _, l in ipairs(lines) do
		local chunks = (l.text == "") and {} or build_row(l)
		if use_overlay and overlay_chunks == nil then
			overlay_chunks = chunks
		else
			virt_lines[#virt_lines + 1] = chunks
		end
		consumed = consumed + 1
	end

	-- Replace the previous overlay (resize / re-render path).
	if active_buf == buf and active_mark then
		pcall(vim.api.nvim_buf_del_extmark, buf, ns, active_mark)
	elseif active_buf and active_buf ~= buf then
		dispose()
	end

	local mark_opts = {
		virt_lines = virt_lines,
		virt_lines_above = false,
		priority = 100,
	}
	if use_overlay and overlay_chunks and #overlay_chunks > 0 then
		mark_opts.virt_text = overlay_chunks
		mark_opts.virt_text_pos = "overlay"
	end

	active_buf = buf
	active_mark = vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, mark_opts)
end

---Show the starter overlay in the current window's buffer, if eligible.
function M.open()
	local buf = vim.api.nvim_get_current_buf()
	render(buf)
end

---@return boolean
local function should_show()
	if not config.enabled or vim.g.beast_no_starter then
		return false
	end
	if vim.fn.argc() ~= 0 then
		return false
	end
	return should_keep(vim.api.nvim_get_current_buf())
end

---@param opts? Beast.Starter.Config
function M.setup(opts)
	config.setup(opts)

	-- Suppress the native intro since we render our own overlay in its place.
	vim.opt.shortmess:append("I")

	augroup = vim.api.nvim_create_augroup("BeastStarter", { clear = true })

	vim.api.nvim_create_autocmd("VimEnter", {
		group = augroup,
		nested = true,
		callback = function()
			if should_show() then
				M.open()
			end
		end,
	})

	-- Mirror `may_show_intro()` — any state change that would suppress the
	-- native intro (text typed, buffer named, buffer split, different buffer
	-- shown, etc.) also clears our overlay.
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertEnter", "BufModifiedSet" }, {
		group = augroup,
		callback = function(args)
			if args.buf == active_buf then
				dispose()
			end
		end,
	})
	vim.api.nvim_create_autocmd({ "BufFilePost", "BufNew", "BufWinLeave", "BufDelete" }, {
		group = augroup,
		callback = function(args)
			if args.buf == active_buf then
				dispose()
			end
		end,
	})

	-- A new normal window, a different buffer shown in the current window,
	-- or any new buffer becoming current all mean the intro conditions no
	-- longer hold (native checks `one_window && curbuf == starter_buf`).
	-- Ignore *floating* windows — popups (which-key, notifications, etc.)
	-- shouldn't dispose the starter overlay.
	local function count_normal_wins()
		local n = 0
		for _, w in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_get_config(w).relative == "" then
				n = n + 1
			end
		end
		return n
	end
	vim.api.nvim_create_autocmd({ "WinNew", "WinEnter", "BufEnter", "BufWinEnter" }, {
		group = augroup,
		callback = function()
			if not active_buf then
				return
			end
			-- Skip transient floating-window events.
			if vim.api.nvim_win_get_config(0).relative ~= "" then
				return
			end
			if count_normal_wins() > 1 then
				dispose()
				return
			end
			if vim.api.nvim_get_current_buf() ~= active_buf then
				dispose()
				return
			end
			if not should_keep(active_buf) then
				dispose()
			end
		end,
	})

	-- Re-render on every resize so the layout follows the new dimensions.
	-- VimResized fires on terminal resize; WinResized covers per-window
	-- changes (`:resize`, etc.). Defer so dimensions/textoff have settled,
	-- and re-open from scratch when something transiently disposed us —
	-- as long as the buffer is still eligible.
	vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
		group = augroup,
		callback = function()
			vim.schedule(function()
				if active_buf and vim.api.nvim_buf_is_valid(active_buf) then
					render(active_buf)
				elseif should_show() then
					M.open()
				end
			end)
		end,
	})

	vim.api.nvim_create_user_command("BeastStarter", function()
		M.open()
	end, { desc = "Open the BeastVim starter overlay on the current buffer" })
end

return M
