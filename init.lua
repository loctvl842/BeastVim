-- Disable built-in rtp plugins we don't use. Must run BEFORE Neovim sources
-- $VIMRUNTIME/plugin/*.vim (i.e. before any require() that triggers init), so
-- the guard `if exists("loaded_<name>")` short-circuits each script.
-- See docs/development/benchmarking.md for the why.
vim.g.loaded_gzip = 1
vim.g.loaded_tarPlugin = 1
vim.g.loaded_zipPlugin = 1
vim.g.loaded_tohtml = 1
vim.g.loaded_tutor = 1
-- netrw: replaced by beast.libs.explorer (neo-tree backend)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

if os.getenv("BEAST_PROFILE") == "1" then
	pcall(function()
		local profile = require("beast.profile")
		profile.start()
		local out = os.getenv("BEAST_PROFILE_OUT") or (vim.fn.stdpath("cache") .. "/beast-profile.txt")
		profile.auto_dump_on_quit(out)
	end)
end

require("beast").setup({
	key = {
		hint = { triggers = { "<leader>", "<localleader>", "f", "z", "g", "[", "]" } },
		mappings = {
			{ "fd", "zd", desc = "Delete fold under cursor" },
			{ "fo", "zo", desc = "Open fold under cursor" },
			{ "fO", "zO", desc = "Open all folds under cursor" },
			{ "fc", "zC", desc = "Close all folds under cursor" },
			{ "fa", "za", desc = "Toggle fold under cursor" },
			{ "fA", "zA", desc = "Toggle all folds under cursor" },
			{ "fv", "zv", desc = "Show cursor line" },
			{ "fM", "zM", desc = "Close all folds" },
			{ "fR", "zR", desc = "Open all folds" },
			{ "fm", "zm", desc = "Fold more" },
			{ "fr", "zr", desc = "Fold less" },
			{ "fx", "zx", desc = "Update folds" },
			{ "fz", "zz", desc = "Center this line" },
			{ "ft", "zt", desc = "Top this line" },
			{ "fb", "zb", desc = "Bottom this line" },
			{ "fg", "zg", desc = "Add word to spell list" },
			{ "fw", "zw", desc = "Mark word as bad/misspelling" },
			{ "fe", "ze", desc = "Right this line" },
			{ "fE", "zE", desc = "Delete all folds in current buffer" },
			{ "fs", "zs", desc = "Left this line" },
			{ "fH", "zH", desc = "Half screen to the left" },
			{ "fL", "zL", desc = "Half screen to the right" },
		},
	},
	explorer = {
		icon = {
			dir_open = "󰝰", -- nf-md-folder_open
			dir_closed = "󰉋", -- nf-md-folder
			-- git = {
			-- 	conflict = "󰞇",
			-- 	modified = "●",
			-- 	renamed = "󰁕",
			-- 	copied = "⧉",
			-- 	deleted = "󰍵",
			-- 	added = "󰐕",
			-- 	untracked = "󰞋",
			-- 	ignored = "󰈉",
			-- },
		},
		mappings = {
			["l"] = "open",
		},
	},
	packer = {
		spec = { { import = "beast.plugins" } },
	},
	treesitter = {
		ensure_installed = {
			"python",
			"lua",
			"javascript",
			"typescript",
			{ "tsx", "typescriptreact" },
			"json",
			"css",
			"html",
		},
		fold = { enable = true },
	},
})

-- ---------------------------------------------------------------------------
-- LSP wiring (hardcoded until BeastVim/<Lang> extension repos exist).
-- ---------------------------------------------------------------------------

-- blink.cmp client capabilities → contributed lazily (forces blink.cmp load
-- only when capabilities are first resolved, i.e. on the first Lsp.register).
Lsp.add_capabilities(function()
	local ok, blink = pcall(require, "blink.cmp")
	if not ok then
		return {}
	end
	return blink.get_lsp_capabilities(nil, false)
end)

Lsp.register("tsgo", {
	cmd = function(dispatchers, config)
		local cmd = "tsgo"
		if (config or {}).root_dir then
			local local_cmd = vim.fs.joinpath(config.root_dir, "node_modules/.bin", cmd)
			if vim.fn.executable(local_cmd) == 1 then
				cmd = local_cmd
			end
		end
		return vim.lsp.rpc.start({ cmd, "--lsp", "--stdio" }, dispatchers)
	end,
	filetypes = {
		"javascript",
		"javascriptreact",
		"typescript",
		"typescriptreact",
	},
	root_dir = function(bufnr, on_dir)
		local root_markers = vim.fn.has("nvim-0.11.3") == 1
				and { { "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb", "bun.lock" }, { ".git" } }
			or { "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb", "bun.lock", ".git" }

		local deno_root = vim.fs.root(bufnr, { "deno.json", "deno.jsonc" })
		local deno_lock_root = vim.fs.root(bufnr, { "deno.lock" })
		local project_root = vim.fs.root(bufnr, root_markers)

		if deno_lock_root and (not project_root or #deno_lock_root > #project_root) then
			return
		end
		if deno_root and (not project_root or #deno_root >= #project_root) then
			return
		end

		on_dir(project_root or vim.fn.getcwd())
	end,
	settings = {
		typescript = {
			inlayHints = {
				parameterNames = { enabled = "literals", suppressWhenArgumentMatchesName = true },
				parameterTypes = { enabled = true },
				variableTypes = { enabled = true },
				propertyDeclarationTypes = { enabled = true },
				functionLikeReturnTypes = { enabled = true },
				enumMemberValues = { enabled = true },
			},
		},
	},
	-- -- HACK: tsgo analyzes the TypeScript project asynchronously. The root cause is
	-- -- that `force_refresh` (resending semanticTokens/full) is insufficient —
	-- -- tsgo only returns a complete token set (including keywords) after
	-- -- receiving a fresh `textDocument/didOpen`. We trigger a silent buffer
	-- -- reload (`:edit`) once tsgo signals it is ready via `$/progress "end"`,
	-- -- falling back to a timer for servers that don't emit progress events.
	-- -- The reload is skipped when the buffer has unsaved changes.
	--  -- NOTE: However, this cause a bug in explorer, where :edit will force the explorer
	--  -- to re-focus on the current Node
	-- on_attach = function(client, bufnr)
	-- 	local client_id = client.id
	-- 	local done = false
	--
	-- 	local function silent_reload()
	-- 		if done then return end
	-- 		if not vim.api.nvim_buf_is_valid(bufnr) then return end
	-- 		if vim.bo[bufnr].modified then return end
	-- 		done = true
	-- 		local win = vim.fn.bufwinid(bufnr)
	-- 		if win == -1 then return end
	-- 		vim.api.nvim_win_call(win, function()
	-- 			vim.cmd("silent! edit")
	-- 		end)
	-- 	end
	--
	-- 	-- Primary trigger: tsgo $/progress "end" signals project is ready.
	-- 	local aug = vim.api.nvim_create_augroup("tsgo-tokens-" .. bufnr, { clear = true })
	-- 	vim.api.nvim_create_autocmd("LspProgress", {
	-- 		group = aug,
	-- 		callback = function(ev)
	-- 			if not (ev.data and ev.data.client_id == client_id) then return end
	-- 			local value = type(ev.data.params) == "table" and ev.data.params.value or nil
	-- 			if type(value) == "table" and value.kind == "end" then
	-- 				vim.schedule(silent_reload)
	-- 			end
	-- 		end,
	-- 	})
	--
	-- 	-- Fallback: reload after 4 s in case tsgo sends no progress events.
	-- 	vim.defer_fn(silent_reload, 4000)
	-- end,
	keys = {
		{ "K", vim.lsp.buf.hover, desc = "Hover", cond = "textDocument/hover" },
		{ "<leader>rn", vim.lsp.buf.rename, desc = "Rename", cond = "textDocument/rename" },
		{
			"<leader>la",
			vim.lsp.buf.code_action,
			mode = { "n", "v" },
			desc = "Code action",
			cond = "textDocument/codeAction",
		},
	},
})

-- ESLint LSP — diagnostics and optional auto-fix on save.
-- Binary: vscode-eslint-language-server (installed via mason or npm)
Lsp.register("eslint", {
	cmd = function(dispatchers, config)
		-- Prefer a project-local or system binary; fall back to the nvim mason install.
		local bins = {
			"vscode-eslint-language-server",
			vim.fn.expand("~/.local/share/nvim/mason/bin/vscode-eslint-language-server"),
		}
		local cmd = "vscode-eslint-language-server"
		for _, bin in ipairs(bins) do
			if vim.fn.executable(bin) == 1 then
				cmd = bin
				break
			end
		end
		if (config or {}).root_dir then
			local local_cmd = vim.fs.joinpath(config.root_dir, "node_modules/.bin", cmd)
			if vim.fn.executable(local_cmd) == 1 then
				cmd = local_cmd
			end
		end
		return vim.lsp.rpc.start({ cmd, "--stdio" }, dispatchers)
	end,
	filetypes = {
		"javascript",
		"javascriptreact",
		"typescript",
		"typescriptreact",
		"vue",
		"svelte",
		"astro",
		"htmlangular",
	},
	workspace_required = true,
	on_attach = function(client, bufnr)
		vim.api.nvim_buf_create_user_command(bufnr, "LspEslintFixAll", function()
			client:request_sync("workspace/executeCommand", {
				command = "eslint.applyAllFixes",
				arguments = {
					{
						uri = vim.uri_from_bufnr(bufnr),
						version = vim.lsp.util.buf_versions[bufnr],
					},
				},
			}, nil, bufnr)
		end, {})
	end,
	root_dir = function(bufnr, on_dir)
		local eslint_config_files = {
			".eslintrc",
			".eslintrc.js",
			".eslintrc.cjs",
			".eslintrc.yaml",
			".eslintrc.yml",
			".eslintrc.json",
			"eslint.config.js",
			"eslint.config.mjs",
			"eslint.config.cjs",
			"eslint.config.ts",
			"eslint.config.mts",
			"eslint.config.cts",
		}
		-- The project root is where the LSP can be started from
		-- As stated in the documentation above, this LSP supports monorepos and simple projects.
		-- We select then from the project root, which is identified by the presence of a package
		-- manager lock file.
		local root_markers = { "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb", "bun.lock" }
		-- Give the root markers equal priority by wrapping them in a table
		root_markers = vim.fn.has("nvim-0.11.3") == 1 and { root_markers, { ".git" } } or vim.list_extend(root_markers, { ".git" })

		-- exclude deno
		if vim.fs.root(bufnr, { "deno.json", "deno.jsonc", "deno.lock" }) then
			return
		end

		-- We fallback to the current working directory if no project root is found
		local project_root = vim.fs.root(bufnr, root_markers) or vim.fn.getcwd()

		-- We know that the buffer is using ESLint if it has a config file
		-- in its directory tree.
		--
		-- Eslint used to support package.json files as config files, but it doesn't anymore.
		-- We keep this for backward compatibility.
		local filename = vim.api.nvim_buf_get_name(bufnr)
		local eslint_config_files_with_package_json = Util.lsp.insert_package_json(eslint_config_files, "eslintConfig", filename)
		local is_buffer_using_eslint = vim.fs.find(eslint_config_files_with_package_json, {
			path = filename,
			type = "file",
			limit = 1,
			upward = true,
			stop = vim.fs.dirname(project_root),
		})[1]
		if not is_buffer_using_eslint then
			return
		end

		on_dir(project_root)
	end,
	root_markers = {
		"eslint.config.js",
		"eslint.config.mjs",
		".eslintrc",
		".eslintrc.js",
		".eslintrc.json",
		"package.json",
		".git",
	},
  -- Refer to https://github.com/Microsoft/vscode-eslint#settings-options for documentation.
  -----@type lspconfig.settings.eslint
  settings = {
    validate = 'on',
    ---@diagnostic disable-next-line: assign-type-mismatch
    packageManager = nil,
    useESLintClass = false,
    experimental = {},
    codeActionOnSave = {
      enable = false,
      mode = 'all',
    },
    format = true,
    quiet = false,
    onIgnoredFiles = 'off',
    rulesCustomizations = {},
    run = 'onType',
    problems = {
      shortenToSingleLine = false,
    },
    -- nodePath configures the directory in which the eslint server should start its node_modules resolution.
    -- This path is relative to the workspace folder (root dir) of the server instance.
    nodePath = '',
    -- use the workspace folder location or the file location (if no workspace folder is open) as the working directory
    workingDirectory = { mode = 'auto' },
    codeAction = {
      disableRuleComment = {
        enable = true,
        location = 'separateLine',
      },
      showDocumentation = {
        enable = true,
      },
    },
  },
  before_init = function(_, config)
    -- The "workspaceFolder" is a VSCode concept. It limits how far the
    -- server will traverse the file system when locating the ESLint config
    -- file (e.g., .eslintrc).
    local root_dir = config.root_dir

    if root_dir then
      config.settings = config.settings or {}
      config.settings.workspaceFolder = {
        uri = root_dir,
        name = vim.fn.fnamemodify(root_dir, ':t'),
      }

      -- Support Yarn2 (PnP) projects
      local pnp_cjs = root_dir .. '/.pnp.cjs'
      local pnp_js = root_dir .. '/.pnp.js'
      if type(config.cmd) == 'table' and (vim.uv.fs_stat(pnp_cjs) or vim.uv.fs_stat(pnp_js)) then
        config.cmd = vim.list_extend({ 'yarn', 'exec' }, config.cmd --[[@as table]])
      end
    end
  end,
  handlers = {
    ['eslint/openDoc'] = function(_, result)
      if result then
        vim.ui.open(result.url)
      end
      return {}
    end,
    ['eslint/confirmESLintExecution'] = function(_, result)
      if not result then
        return
      end
      return 4 -- approved
    end,
    ['eslint/probeFailed'] = function()
      vim.notify('[lspconfig] ESLint probe failed.', vim.log.levels.WARN)
      return {}
    end,
    ['eslint/noLibrary'] = function()
      vim.notify('[lspconfig] Unable to find ESLint library.', vim.log.levels.WARN)
      return {}
    end,
  },
})

-- Save & format: LSP format + ESLint fix-all, then write.
vim.keymap.set("n", "<leader>W", function()
	vim.lsp.buf.format({ async = false })
	-- vim.lsp.buf.code_action({
	-- 	context = { only = { "source.fixAll.eslint" }, diagnostics = {} },
	-- 	apply = true,
	-- })
	vim.cmd("write")
end, { desc = "Save & format" })

Lsp.register("lua_ls", {
	cmd = { "lua-language-server" },
	filetypes = { "lua" },
	root_markers = { ".luarc.json", ".luarc.jsonc", ".git" },
	settings = {
		Lua = {
			workspace = { checkThirdParty = false },
			telemetry = { enable = false },
			diagnostics = { globals = { "vim" } },
			completion = { callSnippet = "Replace" },
		},
	},
	keys = {
		{ "K", vim.lsp.buf.hover, desc = "Hover", cond = "textDocument/hover" },
		-- { "gd", vim.lsp.buf.definition, desc = "Go to definition", cond = "textDocument/definition" },
		-- { "gD", vim.lsp.buf.declaration, desc = "Go to declaration", cond = "textDocument/declaration" },
		-- { "gr", vim.lsp.buf.references, desc = "References", cond = "textDocument/references" },
		-- { "gi", vim.lsp.buf.implementation, desc = "Implementation", cond = "textDocument/implementation" },
		{ "<leader>rn", vim.lsp.buf.rename, desc = "Rename", cond = "textDocument/rename" },
		{
			"<leader>la",
			vim.lsp.buf.code_action,
			mode = { "n", "v" },
			desc = "Code action",
			cond = "textDocument/codeAction",
		},
	},
})
