-- BeastVim Root Detection Utility
--
-- Detection strategies (priority order):
--   1. "lang" - Language-specific root markers based on buffer filetype (HIGHEST PRIORITY)
--      - Python: pyproject.toml, setup.py, setup.cfg, requirements.txt, Pipfile, pyrightconfig.json
--      - Lua: nvim-pack-lock.json, lazy-lock.json, stylua.toml
--      - HTML: package.json
--      - More specific than .git for monorepos
--      - Add more in lua/beastvim/plugins/coding/lang/*.lua (root_spec field)
--   2. "lsp" - Uses LSP workspace folders and root_dir from attached clients
--   3. { ".git", "lua" } - Common project markers
--   4. "cwd" - Falls back to current working directory
--
-- Customization:
--   vim.g.root_spec = { "lang", "lsp", { ".git", "Cargo.toml" }, "cwd" }

---@class beast.util.root
---@overload fun(opts?: {buf?: number}): string
local M = setmetatable({}, {
	__call = function(m, ...)
		return m.get(...)
	end,
})

---@class BeastRoot
---@field paths string[]
---@field spec BeastRootSpec

---@alias BeastRootFn fun(buf: number): (string|string[])
---@alias BeastRootSpec string|string[]|BeastRootFn

-- Default detection spec: try language-specific patterns first, then LSP, then .git/lua, then cwd
---@type BeastRootSpec[]
M.spec = { "lang", "lsp", { ".git", "lua" }, "cwd" }

-- Detectors registry
M.detectors = {}

-- Per-buffer cache
---@type table<number, string>
M.cache = {}

-- Language-specific root patterns (loaded lazily)
---@type table<string, string[]>?
M._lang_patterns = nil

-- CWD detector - returns current working directory
function M.detectors.cwd()
	return { vim.uv.cwd() }
end

-- LSP detector - extracts roots from attached LSP clients
---@param buf number
---@return string[]
function M.detectors.lsp(buf)
	local bufpath = M.bufpath(buf)
	if not bufpath then
		return {}
	end

	local roots = {} ---@type string[]
	local clients = vim.lsp.get_clients({ bufnr = buf })

	-- Filter out ignored LSP clients
	clients = vim.tbl_filter(function(client)
		return not vim.tbl_contains(vim.g.root_lsp_ignore or {}, client.name)
	end, clients) --[[@as vim.lsp.Client[] ]]

	-- Collect workspace folders and root_dir from LSP clients
	for _, client in pairs(clients) do
		local workspace = client.config.workspace_folders
		for _, ws in pairs(workspace or {}) do
			roots[#roots + 1] = vim.uri_to_fname(ws.uri)
		end
		if client.root_dir then
			roots[#roots + 1] = client.root_dir
		end
	end

	-- Filter paths to ensure buffer is inside the root
	return vim.tbl_filter(function(path)
		path = M.realpath(path)
		return path ~= nil and bufpath:find(path, 1, true) == 1
	end, roots)
end

-- Pattern detector - walks upward looking for marker files
---@param buf number
---@param patterns string[]|string
---@return string[]
function M.detectors.pattern(buf, patterns)
	patterns = type(patterns) == "string" and { patterns } or patterns
	---@cast patterns string[]
	local path = M.bufpath(buf) or vim.uv.cwd()

	local pattern = vim.fs.find(function(name)
		for _, p in ipairs(patterns) do
			-- Exact match
			if name == p then
				return true
			end
			-- Wildcard match (e.g., "*.toml")
			if p:sub(1, 1) == "*" and name:find(vim.pesc(p:sub(2)) .. "$") then
				return true
			end
		end
		return false
	end, { path = path, upward = true })[1]

	return pattern and { vim.fs.dirname(pattern) } or {}
end

-- Language-specific detector - uses filetype-specific patterns
-- Two-pass detection strategy for consistent root across files in same directory:
--
-- Pass 1 (Filetype-specific):
--   - If buffer has a filetype (e.g., "python"), check its specific patterns first
--   - Python file → check for requirements.txt, pyproject.toml, setup.py, etc.
--   - Lua file → check for lazy-lock.json, stylua.toml, etc.
--   - If found, return immediately (closest match wins)
--
-- Pass 2 (All patterns fallback):
--   - If Pass 1 finds nothing, try ALL language patterns from all languages
--   - This ensures config files (yaml, json, md) in Python projects still find requirements.txt
--   - Example: config.yaml in GraphValidationFramework/ finds requirements.txt → same root
--   - Prevents files in same directory from having different roots based on filetype
--
-- Why this matters:
--   Without Pass 2: agent_factory.py (Python) → GraphValidationFramework/ ✓
--                   config.yaml (YAML) → OfficeATC/ ✗ (uses .git from parent)
--   With Pass 2:    Both files → GraphValidationFramework/ ✓ (consistent)
---@param buf number
---@return string[]
function M.detectors.lang(buf)
	-- Lazy load language patterns
	if not M._lang_patterns then
		local ok, lang = pcall(require, "beastvim.plugins.coding.lang")
		if ok then
			local agg = lang.aggregate()
			M._lang_patterns = agg.root_patterns or {}
		else
			M._lang_patterns = {}
		end
	end

	-- Get filetype for buffer
	local ft = vim.bo[buf].filetype

	-- If filetype not set yet, try to detect from filename
	if not ft or ft == "" then
		local bufname = vim.api.nvim_buf_get_name(buf)
		if bufname and bufname ~= "" then
			-- Extract extension and map to common filetypes
			local ext = bufname:match("%.([^.]+)$")
			if ext then
				local ext_to_ft = {
					py = "python",
					lua = "lua",
					html = "html",
					css = "css",
					js = "javascript",
					ts = "typescript",
					jsx = "javascriptreact",
					tsx = "typescriptreact",
					toml = "toml",
					xml = "xml",
				}
				ft = ext_to_ft[ext]
			end
		end
	end

	-- Try filetype-specific patterns first (if we have a filetype)
	if ft and ft ~= "" then
		local patterns = M._lang_patterns[ft]
		if patterns and #patterns > 0 then
			local result = M.detectors.pattern(buf, patterns)
			if result and #result > 0 then
				return result
			end
		end
	end

	-- Fallback: collect ALL language-specific patterns and try them
	-- This ensures files like config.yaml in Python projects still find requirements.txt
	local all_patterns = {}
	local seen = {}
	for _, patterns in pairs(M._lang_patterns) do
		for _, pattern in ipairs(patterns) do
			if not seen[pattern] then
				seen[pattern] = true
				table.insert(all_patterns, pattern)
			end
		end
	end

	if #all_patterns == 0 then
		return {}
	end

	-- Try all language patterns (closest match wins)
	return M.detectors.pattern(buf, all_patterns)
end

-- Get realpath of buffer
---@param buf number
---@return string?
function M.bufpath(buf)
	return M.realpath(vim.api.nvim_buf_get_name(assert(buf)))
end

-- Get realpath of current working directory
---@return string
function M.cwd()
	return M.realpath(vim.uv.cwd()) or ""
end

-- Normalize path and resolve symlinks (Unix only)
---@param path string?
---@return string?
function M.realpath(path)
	if path == "" or path == nil then
		return nil
	end

	-- Only resolve symlinks on Unix
	if vim.fn.has("win32") == 0 then
		local rp = vim.uv.fs_realpath(path)
		---@cast rp string?
		path = rp or path
	end

	-- Normalize path separators
	return vim.fs.normalize(path)
end

-- Convert spec to detector function
---@param spec BeastRootSpec
---@return BeastRootFn
function M.resolve(spec)
	if M.detectors[spec] then
		return M.detectors[spec]
	elseif type(spec) == "function" then
		return spec
	end
	-- Default to pattern detector
	return function(buf)
		return M.detectors.pattern(buf, spec)
	end
end

-- Detect root directories for buffer
---@param opts? { buf?: number, spec?: BeastRootSpec[], all?: boolean }
---@return BeastRoot[]
function M.detect(opts)
	opts = opts or {}
	opts.spec = opts.spec or type(vim.g.root_spec) == "table" and vim.g.root_spec or M.spec
	opts.buf = (opts.buf == nil or opts.buf == 0) and vim.api.nvim_get_current_buf() or opts.buf

	local ret = {} ---@type BeastRoot[]

	for _, spec in ipairs(opts.spec) do
		local paths = M.resolve(spec)(opts.buf)
		paths = paths or {}
		paths = type(paths) == "table" and paths or { paths }
		---@cast paths string[]

		local roots = {} ---@type string[]
		for _, p in ipairs(paths) do
			local pp = M.realpath(p)
			if pp and not vim.tbl_contains(roots, pp) then
				roots[#roots + 1] = pp
			end
		end

		-- Sort by path length (longest first = innermost)
		table.sort(roots, function(a, b)
			return #a > #b
		end)

		if #roots > 0 then
			ret[#ret + 1] = { spec = spec, paths = roots }
			if opts.all == false then
				break
			end
		end
	end

	return ret
end

-- Display info about detected roots
function M.info()
	local spec = type(vim.g.root_spec) == "table" and vim.g.root_spec or M.spec
	local roots = M.detect({ all = true })

	local lines = {} ---@type string[]
	local first = true

	-- Build markdown content
	for _, root in ipairs(roots) do
		for _, path in ipairs(root.paths) do
			local check = first and "x" or " "
			---@diagnostic disable-next-line: param-type-mismatch
			local spec_str = type(root.spec) == "table" and table.concat(root.spec, ", ") or tostring(root.spec)
			table.insert(lines, string.format("- [%s] `%s` **(%s)**", check, path, spec_str))
			first = false
		end
	end

	table.insert(lines, "```lua")
	table.insert(lines, "vim.g.root_spec = " .. vim.inspect(spec))
	table.insert(lines, "```")

	-- Use notify popup for rich markdown display
	vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, {
		title = "BeastVim Root Detection",
	})

	return roots[1] and roots[1].paths[1] or vim.uv.cwd()
end

-- Get root directory for buffer (with caching)
---@param opts? {normalize?: boolean, buf?: number}
---@return string
function M.get(opts)
	opts = opts or {}
	local buf = opts.buf or vim.api.nvim_get_current_buf()
	local ret = M.cache[buf]

	if not ret then
		local roots = M.detect({ all = false, buf = buf })
		ret = roots[1] and roots[1].paths[1] or vim.uv.cwd()
		M.cache[buf] = ret
	end

	if opts and opts.normalize then
		return ret
	end

	-- Return path with platform-specific separators
	local is_win = vim.fn.has("win32") == 1
	return is_win and ret:gsub("/", "\\") or ret
end

-- Find .git root from current root
---@return string
function M.git()
	local root = M.get()
	local git_root = vim.fs.find(".git", { path = root, upward = true })[1]
	local ret = git_root and vim.fn.fnamemodify(git_root, ":h") or root
	return ret
end

-- Setup autocmds for cache invalidation
function M.setup()
	vim.api.nvim_create_autocmd({ "LspAttach", "BufWritePost", "DirChanged", "BufEnter", "FileType" }, {
		group = vim.api.nvim_create_augroup("BeastVim-root_cache", { clear = true }),
		callback = function(event)
			M.cache[event.buf] = nil
		end,
	})
end

return M
