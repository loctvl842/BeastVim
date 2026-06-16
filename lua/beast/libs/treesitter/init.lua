local config = require("beast.libs.treesitter.config")

local M = {}

---@type Beast.Lib.Meta
M.meta = { name = "treesitter", description = "Treesitter parser management and auto-install" }

M.enabled = false

local augroup

-- Track buffers where we've already started treesitter
---@type table<number, boolean>
local started = {}

-- Track parsers we've already triggered install for
---@type table<string, boolean>
local installing = {}

--- Check if a treesitter parser is available for the given language.
---@param lang string
---@return boolean
local function has_parser(lang)
	local ok = pcall(vim.treesitter.language.inspect, lang)
	return ok
end

--- Get the treesitter language for a buffer's filetype.
---@param buf number
---@return string?
local function get_lang(buf)
	local ft = vim.bo[buf].filetype
	-- stylua: ignore
	if ft == "" then return nil end
	local ok, lang = pcall(vim.treesitter.language.get_lang, ft)
	return ok and lang or ft
end

-- Forward declaration (ensure_parser callback references start_buf)
local start_buf

--- Attempt async parser installation for a language.
--- After successful install, re-triggers start_buf on all matching buffers.
---@param lang string
---@param buf number The buffer that triggered this install
local function ensure_parser(lang, buf)
	-- stylua: ignore
	if installing[lang] then return end
	-- stylua: ignore
	if has_parser(lang) then return end

	-- Check if the lang is in ensure_installed
	local should_install = false
	for _, name in ipairs(config.ensure_installed) do
		if name == lang then
			should_install = true
			break
		end
	end
	-- stylua: ignore
	if not should_install then return end

	installing[lang] = true

	local parser_info = require("beast.libs.treesitter.parsers").get(lang)
	local install = require("beast.libs.treesitter.install")

	install.install(lang, parser_info.url, parser_info.revision, { location = parser_info.location }, function(ok, err)
		if not ok then
			installing[lang] = nil -- allow retry on transient failures
			vim.notify(string.format("[beast.treesitter] Failed to install parser for '%s': %s", lang, tostring(err)), vim.log.levels.WARN)
			return
		end

		-- Re-trigger start_buf on buffers waiting for this parser
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_loaded(b) and not started[b] then
				local ft_lang = get_lang(b)
				if ft_lang == lang then
					start_buf(b)
				end
			end
		end
	end)
end

--- Start treesitter highlighting (and optionally folding) for a buffer.
---@param buf number
start_buf = function(buf)
	-- stylua: ignore
	if started[buf] then return end
	-- stylua: ignore
	if not vim.api.nvim_buf_is_valid(buf) then return end

	local lang = get_lang(buf)
	-- stylua: ignore
	if not lang then return end

	-- Try installing if configured
	ensure_parser(lang, buf)

	-- Only start if parser is available
	-- stylua: ignore
	if not has_parser(lang) then return end

	if config.highlight.enable then
		pcall(vim.treesitter.start, buf, lang)
	end

	if config.fold.enable then
		local win = vim.fn.bufwinid(buf)
		if win ~= -1 then
			View.win.wo(win, "foldmethod", "expr")
			View.win.wo(win, "foldexpr", "v:lua.vim.treesitter.foldexpr()")
		end
	end

	started[buf] = true

	-- Pull the richer upstream query set (highlights/injections/indents/locals
	-- + context) into the install dir, even for parsers Neovim ships built-in.
	-- When new files land, bust Neovim's treesitter query cache (via an rtp
	-- touch — see its `OptionSet runtimepath` handler) and restart highlighting
	-- so the upstream queries replace the cached builtin ones immediately.
	require("beast.libs.treesitter.install").ensure_queries(lang, function(changed)
		-- stylua: ignore
		if not changed then return end
		vim.schedule(function()
			pcall(vim.api.nvim_set_option_value, "runtimepath", vim.o.runtimepath, {})
			for b in pairs(started) do
				if vim.api.nvim_buf_is_valid(b) and get_lang(b) == lang then
					pcall(vim.treesitter.stop, b)
					if config.highlight.enable then
						pcall(vim.treesitter.start, b, lang)
					end
				end
			end
			if package.loaded["beast.libs.treesitter.context"] then
				pcall(function()
					require("beast.libs.treesitter.context").refresh()
				end)
			end
		end)
	end)
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

function M.setup(opts)
	config.setup(opts)
	require("beast").apply_highlights("beast.libs.treesitter.highlights")
	require("beast").apply_highlights("beast.libs.treesitter.context.highlights")
end

function M.enable()
	-- stylua: ignore
	if M.enabled then return end
	M.enabled = true

	augroup = vim.api.nvim_create_augroup("BeastTreesitter", { clear = true })

	vim.api.nvim_create_autocmd("FileType", {
		group = augroup,
		callback = function(ev)
			start_buf(ev.buf)
		end,
	})

	-- Clean up tracking when buffers are wiped
	vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
		group = augroup,
		callback = function(ev)
			started[ev.buf] = nil
		end,
	})

	-- Start on any already-loaded buffers
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype ~= "" then
			start_buf(buf)
		end
	end

	if config.context.enable then
		require("beast.libs.treesitter.context").enable()
	end
end

function M.disable()
	-- stylua: ignore
	if not M.enabled then return end
	M.enabled = false

	if augroup then
		vim.api.nvim_del_augroup_by_id(augroup)
		augroup = nil
	end

	if package.loaded["beast.libs.treesitter.context"] then
		require("beast.libs.treesitter.context").disable()
	end

	-- Stop treesitter on all tracked buffers
	for buf in pairs(started) do
		if vim.api.nvim_buf_is_valid(buf) then
			pcall(vim.treesitter.stop, buf)
		end
	end

	started = {}
	installing = {}
end

return M
