-- Per-language context query loader.
--
-- Context queries (`@context` / `@context.start` / `@context.end` /
-- `@context.final`) describe which treesitter nodes contribute a sticky header
-- line and where that header begins/ends.
--
-- They are NOT vendored in this repo. They live next to the other treesitter
-- query files in the install dir (`stdpath('data')/site/queries/<lang>/
-- context.scm`), downloaded by the treesitter installer alongside the rest of
-- the upstream query set (see `install.ensure_queries`). This module only reads
-- and parses them; downloading + post-download refresh is driven by the
-- treesitter lib's `start_buf`.
--
-- We read + parse the file directly rather than going through
-- `vim.treesitter.query.get(lang, "context")` so a missing-then-downloaded file
-- is picked up immediately on the next lookup without depending on Neovim's
-- query cache being cleared.

local M = {}

-- lang -> compiled Query (parsed) or false (present but failed to parse). A
-- missing entry means "not loaded yet"; we deliberately do not cache the
-- file-absent case so a later download is picked up.
---@type table<string, vim.treesitter.Query|false>
local cache = {}

---@return string
local function queries_root()
	return require("beast.libs.treesitter.install").get_install_dir() .. "/queries"
end

---@param lang string
---@return string
local function path_for(lang)
	return queries_root() .. "/" .. lang .. "/context.scm"
end

--- Return the compiled context query for `lang`, or nil when none is installed
--- yet (or it fails to parse).
---@param lang string
---@return vim.treesitter.Query?
function M.get(lang)
	local cached = cache[lang]
	if cached ~= nil then
		return cached or nil
	end

	local path = path_for(lang)
	if vim.fn.filereadable(path) ~= 1 then
		return nil
	end

	local source = table.concat(vim.fn.readfile(path), "\n")
	local ok, query = pcall(vim.treesitter.query.parse, lang, source)
	cache[lang] = (ok and query) or false
	return (ok and query) or nil
end

--- Whether a usable context query is installed for `lang`.
---@param lang string
---@return boolean
function M.has(lang)
	return M.get(lang) ~= nil
end

--- List the languages that currently have a context query file installed.
---@return string[]
function M.languages()
	local langs = {}
	for _, path in ipairs(vim.fn.globpath(queries_root(), "*/context.scm", false, true)) do
		langs[#langs + 1] = vim.fn.fnamemodify(path, ":h:t")
	end
	table.sort(langs)
	return langs
end

return M
