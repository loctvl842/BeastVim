local fs = vim.fs
local uv = vim.uv

local M = {}

--- Query files to download from nvim-treesitter (comprehensive Neovim-compatible captures).
local QUERY_FILES = { "highlights.scm", "folds.scm", "indents.scm", "injections.scm", "locals.scm" }
local NVIM_TS_QUERY_BASE = "https://raw.githubusercontent.com/nvim-treesitter/nvim-treesitter/main/runtime/queries"

--- Sticky-context queries live in a separate repo (nvim-treesitter-context), not
--- in nvim-treesitter, so they are fetched from their own base URL.
local NVIM_TS_CONTEXT_QUERY_BASE = "https://raw.githubusercontent.com/nvim-treesitter/nvim-treesitter-context/master/queries"

--- Default parser install directory (prepended to runtimepath).
---@return string
function M.get_install_dir()
	return fs.joinpath(vim.fn.stdpath("data") --[[@as string]], "site")
end

--- Get the parser directory.
---@return string
function M.get_parser_dir()
	return fs.joinpath(M.get_install_dir(), "parser")
end

--- Run an async shell command, returning result via callback.
---@param cmd string[]
---@param opts? vim.SystemOpts
---@param on_done fun(ok: boolean, output: string)
local function async_cmd(cmd, opts, on_done)
	vim.system(cmd, opts or {}, function(result)
		vim.schedule(function()
			local ok = result.code == 0
			local output = ok and (result.stdout or "") or (result.stderr or result.stdout or "")
			on_done(ok, output)
		end)
	end)
end

--- Download a single query file, cleaning up empty/failed results (e.g. a 404
--- for a language that has no such query upstream) so the install dir never
--- shadows a builtin query with an empty file. `on_done(ok)` reports whether a
--- non-empty file now exists at `target`.
---@param url string
---@param target string
---@param on_done fun(ok: boolean)
local function download_query(url, target, on_done)
	async_cmd({ "curl", "--silent", "--fail", "-L", url, "--output", target }, nil, function(ok)
		local st = uv.fs_stat(target)
		if not ok or not st or st.size == 0 then
			pcall(uv.fs_unlink, target)
			on_done(false)
			return
		end
		on_done(true)
	end)
end

--- Download the sticky-context query for a single language into the install
--- dir's `queries/<lang>/context.scm`. `on_done(ok)` reports whether a non-empty
--- file now exists.
---@param lang string
---@param on_done? fun(ok: boolean)
function M.install_context_query(lang, on_done)
	on_done = on_done or function() end
	local query_dst = fs.joinpath(M.get_install_dir(), "queries", lang)
	vim.fn.mkdir(query_dst, "p")
	download_query(string.format("%s/%s/context.scm", NVIM_TS_CONTEXT_QUERY_BASE, lang), fs.joinpath(query_dst, "context.scm"), on_done)
end

-- Languages whose query set has already been ensured this session, so we only
-- probe/download once per language.
---@type table<string, true>
local ensured = {}

--- Ensure the full upstream query set (highlights/folds/indents/injections/
--- locals + context) exists in the install dir for `lang`, downloading any
--- missing files from nvim-treesitter. This lets beast use the richer upstream
--- queries instead of Neovim's bundled subset, even for parsers Neovim ships
--- built-in (where the per-parser install path never runs). `on_done(changed)`
--- reports whether any new file was written, so callers can refresh consumers.
---@param lang string
---@param on_done? fun(changed: boolean)
function M.ensure_queries(lang, on_done)
	on_done = on_done or function() end
	if ensured[lang] then
		on_done(false)
		return
	end
	ensured[lang] = true

	local query_dst = fs.joinpath(M.get_install_dir(), "queries", lang)

	-- Collect the files that are not already present.
	local pending = {} ---@type { url: string, target: string }[]
	for _, filename in ipairs(QUERY_FILES) do
		local target = fs.joinpath(query_dst, filename)
		if vim.fn.filereadable(target) ~= 1 then
			pending[#pending + 1] = { url = string.format("%s/%s/%s", NVIM_TS_QUERY_BASE, lang, filename), target = target }
		end
	end
	local need_context = vim.fn.filereadable(fs.joinpath(query_dst, "context.scm")) ~= 1

	if #pending == 0 and not need_context then
		on_done(false)
		return
	end

	vim.fn.mkdir(query_dst, "p")

	local changed = false
	local remaining = #pending + (need_context and 1 or 0)
	local function tick(ok)
		changed = changed or ok
		remaining = remaining - 1
		if remaining == 0 then
			on_done(changed)
		end
	end

	for _, item in ipairs(pending) do
		download_query(item.url, item.target, tick)
	end
	if need_context then
		M.install_context_query(lang, tick)
	end
end

--- Download comprehensive query files from nvim-treesitter, falling back to grammar repo queries.
--- Downloads all QUERY_FILES (plus the sticky-context query) in parallel; when
--- all finish, calls on_done.
---@param lang string
---@param compile_dir string Path to the extracted grammar source (has queries/ subdir)
---@param on_done fun()
local function install_queries(lang, compile_dir, on_done)
	local query_dst = fs.joinpath(M.get_install_dir(), "queries", lang)
	vim.fn.mkdir(query_dst, "p")

	-- First, copy whatever the grammar repo ships as a baseline
	local query_src = fs.joinpath(compile_dir, "queries")
	if uv.fs_stat(query_src) then
		for name in vim.fs.dir(query_src) do
			uv.fs_copyfile(fs.joinpath(query_src, name), fs.joinpath(query_dst, name))
		end
	end

	-- Then overlay with nvim-treesitter's more comprehensive queries plus the
	-- sticky-context query (parallel downloads).
	local remaining = #QUERY_FILES + 1
	local function tick()
		remaining = remaining - 1
		if remaining == 0 then
			-- Mark ensured so a later ensure_queries() call is a no-op.
			ensured[lang] = true
			on_done()
		end
	end

	for _, filename in ipairs(QUERY_FILES) do
		local url = string.format("%s/%s/%s", NVIM_TS_QUERY_BASE, lang, filename)
		local target = fs.joinpath(query_dst, filename)
		download_query(url, target, tick)
	end
	M.install_context_query(lang, tick)
end

--- Install a parser for a language from a GitHub URL.
--- Flow: curl tarball → extract → tree-sitter build → copy .so
---@param lang string
---@param url string GitHub repo URL
---@param revision? string Git ref (tag, branch, or commit SHA). Defaults to "main".
---@param opts? { location?: string, generate?: boolean }
---@param on_done? fun(ok: boolean, err?: string)
function M.install(lang, url, revision, opts, on_done)
	on_done = on_done or function() end
	opts = opts or {}
	revision = revision or "HEAD"

	local cache_dir = vim.fn.stdpath("cache") --[[@as string]]
	local parser_dir = M.get_parser_dir()
	local project_name = "tree-sitter-" .. lang
	local tarball = fs.joinpath(cache_dir, project_name .. ".tar.gz")
	local extract_dir = fs.joinpath(cache_dir, project_name .. "-extract")
	local source_dir = fs.joinpath(cache_dir, project_name)

	-- Ensure parser directory exists
	vim.fn.mkdir(parser_dir, "p")

	url = url:gsub("%.git$", "")
	local tarball_url = string.format("%s/archive/%s.tar.gz", url, revision)

	vim.notify(string.format("[beast.treesitter] Installing %s parser...", lang), vim.log.levels.INFO)

	-- Step 1: Download tarball
	async_cmd(
		{
			"curl",
			"--silent",
			"--fail",
			"--show-error",
			"--retry",
			"3",
			"-L",
			tarball_url,
			"--output",
			tarball,
		},
		nil,
		function(ok, output)
			if not ok then
				on_done(false, "Download failed: " .. output)
				return
			end

			-- Step 2: Extract tarball
			vim.fn.mkdir(extract_dir, "p")
			async_cmd({ "tar", "-xzf", tarball, "-C", extract_dir }, nil, function(ok2, output2)
				-- Clean up tarball
				pcall(uv.fs_unlink, tarball)

				if not ok2 then
					pcall(vim.fn.delete, extract_dir, "rf")
					on_done(false, "Extraction failed: " .. output2)
					return
				end

				-- Find the extracted directory (GitHub archives as {repo}-{ref}/)
				local extracted = nil
				for name, type in vim.fs.dir(extract_dir) do
					if type == "directory" then
						extracted = fs.joinpath(extract_dir, name)
						break
					end
				end

				if not extracted then
					pcall(vim.fn.delete, extract_dir, "rf")
					on_done(false, "Could not find extracted directory")
					return
				end

				-- Rename to a clean path
				pcall(vim.fn.delete, source_dir, "rf")
				uv.fs_rename(extracted, source_dir)
				pcall(vim.fn.delete, extract_dir, "rf")

				-- Determine compile location
				local compile_dir = source_dir
				if opts.location then
					compile_dir = fs.joinpath(source_dir, opts.location)
				end

				-- Step 3: Compile with tree-sitter build
				local parser_output = fs.joinpath(compile_dir, "parser.so")
				async_cmd({ "tree-sitter", "build", "-o", parser_output }, { cwd = compile_dir }, function(ok3, output3)
					if not ok3 then
						pcall(vim.fn.delete, source_dir, "rf")
						on_done(false, "Compilation failed: " .. output3)
						return
					end

					-- Step 4: Copy parser.so to install dir
					local target = fs.joinpath(parser_dir, lang .. ".so")
					local copy_ok, copy_err = uv.fs_copyfile(parser_output, target)

					if not copy_ok then
						pcall(vim.fn.delete, source_dir, "rf")
						on_done(false, "Copy failed: " .. tostring(copy_err))
						return
					end

					-- Step 5: Install query files then finish
					install_queries(lang, compile_dir, function()
						pcall(vim.fn.delete, source_dir, "rf")
						vim.notify(string.format("[beast.treesitter] Parser installed: %s", lang), vim.log.levels.INFO)
						on_done(true)
					end)
				end)
			end)
		end
	)
end

return M
