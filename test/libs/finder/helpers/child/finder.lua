-- Child-side half of the finder test helpers. Loaded inside the child Nvim (never in the spec
-- process) by `require("test.libs.finder.helpers.finder").setup()`, which publishes it as the
-- global `FH`. Specs reach it through the spec-side wrappers of `helpers/finder.lua`; code that
-- runs in the child itself (`n.exec_lua(function() ... end)`) can call `FH.*` directly, e.g. to
-- register a fake source whose `get` is a function. See helpers/finder.lua for the full API.
--
-- Everything here goes through the finder's public surface (`finder.open/close`, mappings,
-- windows) so specs keep passing while the finder's internals are refactored.
local H = {}

---@type string[]
H.toasts = {}

--- Prepare the child: a wide screen (titles show whole), a recording `Toast`, no indexing of the cwd.
function H.boot()
	vim.o.columns = 200
	vim.o.lines = 50
	H.toasts = {}
	_G.Toast = function(msg)
		H.toasts[#H.toasts + 1] = msg
	end
	-- `finder.setup` would start the grep index of the cwd; not wanted in a test.
	package.loaded["beast.libs.finder.source.live_grep.engine.index"] = { setup = function() end }
end

--- Let timers and scheduled callbacks run.
---@param ms? integer
function H.settle(ms)
	vim.wait(ms or 150, function()
		return false
	end, 10)
end

--- Wait until `cond()` is truthy (true) or give up (false).
---@param cond fun(): any
---@param ms? integer
---@return boolean
function H.wait(cond, ms)
	return vim.wait(ms or 1000, cond, 10)
end

--- Register a source for `finder.open(name)` without touching the real registry files.
---@param name string
---@param spec table
---@return table
function H.fake_source(name, spec)
	package.loaded["beast.libs.finder.source." .. name] = spec
	return spec
end

--- A sync match-pipeline source over `texts` (each becomes `{ text = t, file = t }`).
---@param name string
---@param texts string[]
---@param extra? table
function H.list_source(name, texts, extra)
	return H.fake_source(
		name,
		vim.tbl_extend("force", {
			live = false,
			async = false,
			get = function()
				local items = {}
				for i, text in ipairs(texts) do
					items[i] = { idx = i, score = 0, text = text, file = text }
				end
				return items
			end,
		}, extra or {})
	)
end

---@return table
function H.finder()
	return require("beast.libs.finder")
end

--- Open a real picker and wait for it to settle.
---@param name string
---@param opts? table
function H.open(name, opts)
	H.finder().open(name, opts)
	H.settle()
end

function H.close()
	H.finder().close()
end

---@class Beast.Test.Pane
---@field win integer
---@field buf integer

--- The picker's windows by role (`input`, `list`, `backdrop`, `preview`); missing roles are nil.
---@return table<string, Beast.Test.Pane>
function H.panes()
	local out = {}
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		local role = vim.bo[buf].filetype:match("^beast%-finder%-(%a+)$")
		if role then
			out[role] = { win = win, buf = buf }
		end
	end
	-- The preview buffer takes the filetype of what it shows, so find it as the remaining float.
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local known = false
		for _, pane in pairs(out) do
			known = known or pane.win == win
		end
		if not known and (vim.api.nvim_win_get_config(win).relative or "") ~= "" then
			local buf = vim.api.nvim_win_get_buf(win)
			if (vim.api.nvim_win_get_config(win).zindex or 50) >= 100 then
				out.preview = { win = win, buf = buf }
			end
		end
	end
	return out
end

--- How many windows of the picker are open (input, list, preview, backdrop).
---@return integer
function H.window_count()
	local count = 0
	for _ in pairs(H.panes()) do
		count = count + 1
	end
	return count
end

--- Run a pane's mapping callback (what pressing `lhs` there does).
---@param lhs string
---@param opts? { pane?: "input"|"list"|"preview", mode?: string }
---@return boolean found
function H.press(lhs, opts)
	opts = opts or {}
	local pane = H.panes()[opts.pane or "input"]
	-- stylua: ignore
	if not pane then return false end
	local mode = opts.mode or (opts.pane == "list" or opts.pane == "preview") and "n" or "i"
	-- Focus the pane (not nvim_buf_call, which would undo a focus change made by the mapping).
	vim.api.nvim_set_current_win(pane.win)
	local map = vim.fn.maparg(lhs, mode, false, true)
	if map and map.callback then
		map.callback()
	end
	H.settle(60)
	return map ~= nil and map.callback ~= nil
end

--- Write `text` into the prompt the way typing does, then wait for the debounce.
---@param text string
---@param wait_ms? integer
function H.type(text, wait_ms)
	local input = H.panes().input
	-- stylua: ignore
	if not input then return end
	local prefix = require("beast.libs.finder.config").prompt_prefix
	vim.api.nvim_buf_set_lines(input.buf, 0, 1, false, { prefix .. text })
	vim.api.nvim_buf_call(input.buf, function()
		vim.api.nvim_exec_autocmds("TextChangedI", { buffer = input.buf })
	end)
	H.settle(wait_ms or 300)
end

--- The prompt text without its prefix.
---@return string
function H.prompt()
	local input = H.panes().input
	-- stylua: ignore
	if not input then return "" end
	local line = vim.api.nvim_buf_get_lines(input.buf, 0, 1, false)[1] or ""
	local prefix = require("beast.libs.finder.config").prompt_prefix
	return line:sub(1, #prefix) == prefix and line:sub(#prefix + 1) or line
end

--- The right-aligned count label in the prompt row ("" when none).
---@return string
function H.count()
	local input = H.panes().input
	-- stylua: ignore
	if not input then return "" end
	for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(input.buf, -1, 0, -1, { details = true })) do
		local virt = mark[4].virt_text
		if virt and mark[4].virt_text_pos == "right_align" then
			return virt[1][1]
		end
	end
	return ""
end

--- The key hint line under the picker ("" when hidden).
---@return string
function H.hint()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local cfg = vim.api.nvim_win_get_config(win)
		if cfg.relative ~= "" and cfg.zindex == 102 and not cfg.focusable then
			return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, 1, false)[1] or ""
		end
	end
	return ""
end

--- The prompt window's title, trimmed ("" when it has none).
---@return string
function H.title()
	local input = H.panes().input
	-- stylua: ignore
	if not input then return "" end
	local title = vim.api.nvim_win_get_config(input.win).title
	if type(title) == "table" then
		title = title[1] and title[1][1] or ""
	end
	return vim.trim(title or "")
end

--- Text of the list rows as drawn (headers included), trimmed.
---@return string[]
function H.rows()
	local list = H.panes().list
	-- stylua: ignore
	if not list then return {} end
	return vim.tbl_map(function(line)
		return vim.trim(line)
	end, vim.api.nvim_buf_get_lines(list.buf, 0, -1, false))
end

--- True when some drawn row contains `needle`.
---@param needle string
---@return boolean
function H.has_row(needle)
	for _, row in ipairs(H.rows()) do
		if row:find(needle, 1, true) then
			return true
		end
	end
	return false
end

--- The preview pane's text ("" when there is no preview).
---@return string
function H.preview_text()
	local preview = H.panes().preview
	-- stylua: ignore
	if not preview then return "" end
	return table.concat(vim.api.nvim_buf_get_lines(preview.buf, 0, -1, false), "\n")
end

--- Toasts shown so far.
---@return string[]
function H.get_toasts()
	return H.toasts
end

--- The last toast shown ("" when none).
---@return string
function H.last_toast()
	return H.toasts[#H.toasts] or ""
end

--- Create a temp dir (symlinks resolved) holding `files` (`{ [relative path] = line or lines }`) and
--- make it the cwd of the child.
---@param files table<string, string|string[]>
---@return string dir
function H.tmpdir(files)
	local dir = vim.fn.resolve(vim.fn.tempname())
	vim.fn.mkdir(dir, "p")
	for name, content in pairs(files) do
		vim.fn.mkdir(vim.fs.dirname(dir .. "/" .. name), "p")
		vim.fn.writefile(type(content) == "table" and content or { content }, dir .. "/" .. name)
	end
	vim.cmd("cd " .. vim.fn.fnameescape(dir))
	return dir
end

return H
