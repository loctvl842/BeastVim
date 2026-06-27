local M = {}

local hl = require("beast.hl_reload")
M.apply_highlights = hl.apply_highlights
M.reload_highlights = hl.reload_highlights

---@class Beast.Config
---@field key? Beast.Key.Config
---@field notify? Beast.Notify.Config
---@field toast? table
---@field explorer? Beast.Explorer.Config
---@field packer? Beast.Packer.Config
---@field treesitter? Beast.Treesitter.Config
---@field finder? Beast.Finder.Config
---@field indent? Beast.Indent.Config
---@field breadcrumb? Beast.Breadcrumb.Config
---@field scroll? Beast.Scroll.Config
---@field image? Beast.Image.Viewer.Opts
---@field starter? Beast.Starter.Config
---@field window? Beast.Window.Config
---@field autopairs? Beast.Autopairs.Config
---@field lsp? Beast.Lsp.Config
local defaults = {}

---@param opts? Beast.Config
function M.setup(opts)
	local user_starter_keys = opts and opts.starter and opts.starter.keys
	local cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
	-- Opt-in: only render the BeastVim key rows when the user explicitly
	-- provided `starter.keys`. Otherwise fall through to the bare native intro.
	if user_starter_keys == nil then
		cfg.starter = cfg.starter or {}
		cfg.starter.keys = {}
	end

	local packer = require("beast.libs.packer")

	require("beast.option")

	_G.Util = require("beast.util") ---@type Beast.Util
	_G.Theme = Util.mod("beast.theme") ---@type Beast.Theme
	_G.Key = Util.mod("beast.libs.key") ---@type Beast.Key
	_G.View = Util.mod("beast.libs.view") ---@type Beast.View
	_G.Icon = Util.mod("beast.icon") ---@type Beast.Icon

	packer.lazy("beast.theme", {
		event = { name = "VimEnter", defer = true },
		init = function()
			_G.Theme = Util.mod("beast.theme")
		end,
		setup = function()
			Theme.setup()
			hl.setup()
			-- Initial theme extraction (colorscheme should be loaded by packer)
			Theme.refresh()
			M.reload_highlights()
		end,
	})

	-- Notification
	packer.lazy("beast.libs.notify", {
		event = { name = "VimEnter", defer = true },
		setup = function(notify)
			notify.setup(cfg.notify or {})
		end,
	})
	packer.lazy("beast.libs.toast", {
		event = { name = "VimEnter", defer = true },
		setup = function(toast)
			_G.Toast = toast
			toast.setup(cfg.toast or {})
		end,
	})

	packer.lazy("beast.libs.confirm", {
		module = "beast.libs.confirm",
		setup = function(confirm)
			confirm.setup()
		end,
	})

	-- Inline image viewer (active only on terminals with a graphics protocol)
	require("beast.libs.image.viewer").setup(cfg.image or {})

	-- Statusline (declarative components, native %! evaluation)
	packer.lazy("beast.libs.statusline", {
		event = { name = "VimEnter", defer = true },
		setup = function(stl)
			local cpn = require("beast.libs.statusline.components")
			stl.setup({
				left = { cpn.git_branch, cpn.diagnostics },
				right = { cpn.macro, cpn.git_commit, cpn.position, cpn.filetype, cpn.shiftwidth, cpn.encoding, cpn.mode },
			})
		end,
	})

	-- Breadcrumb / winbar (lazy — deferred past first screen update)
	packer.lazy("beast.libs.breadcrumb", {
		event = {
			{
				name = "BufWinEnter",
				defer = true,
				cond = function()
					return vim.bo.buftype == "" and vim.api.nvim_buf_get_name(0) ~= ""
				end,
			},
			{
				name = "BufWritePost",
				defer = true,
				cond = function()
					return vim.bo.buftype == "" and vim.api.nvim_buf_get_name(0) ~= ""
				end,
			},
		},
		setup = function(breadcrumb)
			breadcrumb.setup(cfg.breadcrumb or {})
		end,
	})

	-- Tabline (lazy — deferred past first screen update)
	packer.lazy("beast.libs.tabline", {
		event = {
			{
				name = "BufWinEnter",
				defer = true,
				cond = function()
					return vim.bo.buftype == "" and vim.api.nvim_buf_get_name(0) ~= ""
				end,
			},
			{
				name = "BufWritePost",
				defer = true,
				cond = function()
					return vim.bo.buftype == "" and vim.api.nvim_buf_get_name(0) ~= ""
				end,
			},
		},
	  -- stylua: ignore
		keys = {
			{ "[B", function() require("beast.libs.tabline").move_prev() end, mode = "n", desc = "Move buffer prev", group = "Tabline" },
      { "]B", function() require("beast.libs.tabline").move_next() end, mode = "n", desc = "Move buffer next", group = "Tabline" },
		},
		init = function()
			vim.opt.showtabline = 0 -- (0: never, 1: always, 2: when there are multiple tabs) - defer to 'tabline'
		end,
		setup = function(tabline)
			tabline.setup({
				max_name_width = 30,
				min_cell_width = 18,
				sidebar_filetypes = { ["beast-explorer"] = "EXPLORER" },
				show_close_button = true,
				show_modified = true,
				show_diagnostics = true,
			})
		end,
	})

	-- Statuscolumn (lazy — deferred past first screen update)
	packer.lazy("beast.libs.statuscolumn", {
		event = {
			{
				name = "BufWinEnter",
				defer = true,
				cond = function()
					return vim.bo.buftype == "" and vim.api.nvim_buf_get_name(0) ~= ""
				end,
			},
			{
				name = "BufWritePost",
				defer = true,
				cond = function()
					return vim.bo.buftype == "" and vim.api.nvim_buf_get_name(0) ~= ""
				end,
			},
		},
		setup = function(stc)
			stc.setup({})
		end,
	})

	-- Git (lazy — attaches per buffer on BufReadPost)
	packer.lazy("beast.libs.git", {
		event = { name = "BufReadPost", defer = true },
	    -- stylua: ignore
	    keys = {
	      { "]c", function() require("beast.libs.git").next_hunk({ target = "all" }) end, mode = "n", desc = "Next hunk", group = "Git" },
	      { "[c", function() require("beast.libs.git").prev_hunk({ target = "all" }) end, mode = "n", desc = "Previous hunk", group = "Git" },
	      { "<leader>gp", function() require("beast.libs.git").preview_hunk() end, mode = { "n", "x" }, desc = "Preview hunk(s)", group = "Git" },
	      { "<leader>gs", function() require("beast.libs.git").stage_hunk() end, mode = { "n", "x" }, desc = "Stage hunk (toggle)", group = "Git" },
	      { "<leader>gu", function() require("beast.libs.git").unstage_hunk() end, mode = { "n", "x" }, desc = "Unstage hunk (explicit)", group = "Git" },
	      { "<leader>gr", function() require("beast.libs.git").reset_hunk() end, mode = { "n", "x" }, desc = "Reset hunk", group = "Git" },
	      { "<leader>g.", function() require("beast.libs.git").repeat_action() end, mode = "n", desc = "Repeat last git action", group = "Git" },
	      { "<leader>gb", function() require("beast.libs.git").blame_line() end, mode = "n", desc = "Blame current line", group = "Git" },
	      { "<leader>gB", function() require("beast.libs.git").blame() end, mode = "n", desc = "Blame file (side window)", group = "Git" },
	      { "<leader>gtb", function() require("beast.libs.git").toggle_current_line_blame() end, mode = "n", desc = "Toggle current-line blame", group = "Git" },
	    },
		setup = function(g)
			g.setup({})
		end,
	})

	local function startup_dir()
		if vim.fn.argc() ~= 1 then
			return
		end

		---@type string
		---@diagnostic disable-next-line: assign-type-mismatch
		local path = vim.fn.argv(0)
		if vim.fn.isdirectory(path) == 1 then
			return vim.fn.fnamemodify(path, ":p"):gsub("/$", "")
		end
	end
	-- Explorer (lazy — deferred to first <leader>e press or VimEnter with no file)
	packer.lazy("beast.libs.explorer", {
		keys = {
			{
				"<leader>e",
				function()
					require("beast.libs.explorer").toggle()
				end,
				desc = "Toggle explorer panel",
				group = "Explorer",
			},
		},
		event = {
			name = "VimEnter",
			defer = true,
			cond = function()
				return startup_dir() ~= nil
			end,
		},
		setup = function(explorer)
			explorer.setup(cfg.explorer or {})

			local dir = startup_dir()
			if dir then
				explorer.open(dir)
			end
		end,
	})

	-- Indent scope indicator (lazy — activate on first buffer with content)
	packer.lazy("beast.libs.indent", {
		event = {
			{
				name = "BufReadPost",
				defer = true,
				cond = function()
					return vim.bo.buftype == "" and vim.api.nvim_buf_get_name(0) ~= ""
				end,
			},
			{
				name = "BufWritePost",
				defer = true,
				cond = function()
					return vim.bo.buftype == "" and vim.api.nvim_buf_get_name(0) ~= ""
				end,
			},
		},
		setup = function(indent)
			indent.setup(cfg.indent or {})
		end,
	})

	-- Treesitter (lazy — enable builtin highlighting + fold on FileType)
	packer.lazy("beast.libs.treesitter", {
		event = {
			name = "FileType",
			defer = true,
			cond = function()
				return vim.bo.buftype == "" and vim.api.nvim_buf_get_name(0) ~= ""
			end,
		},
		setup = function(ts)
			ts.setup(cfg.treesitter or {})
			ts.enable()
		end,
	})

	packer.lazy("beast.libs.finder", {
		setup = function(finder)
			finder.setup(cfg.finder or {})
		end,
	   -- stylua: ignore
		keys = {
			{ "<leader>f", function() require("beast.libs.finder").open("files") end, desc = "Find files" },
			{ "<leader>b", function() require("beast.libs.finder").open("buffers") end, desc = "Find buffers" },
			{ "<leader>F", function() require("beast.libs.finder").open("live_grep") end, desc = "Live grep" },
			{ "<leader>h", function() require("beast.libs.finder").open("help_tags") end, desc = "Help tags" },
			{
				"<leader>c",
				function()
					local original = vim.g.colors_name or "default"
					local confirmed = false
					require("beast.libs.finder").open("colorschemes", {
						preview = false,
						on_preview = function(item)
							pcall(vim.cmd.colorscheme, item.text)
						end,
						on_close = function()
							if not confirmed then
								pcall(vim.cmd.colorscheme, original)
							end
						end,
					})
				end,
				desc = "Colorschemes",
			},
		},
	})

	-- Smooth viewport scrolling (lazy — activate after first buffer read)
	packer.lazy("beast.libs.scroll", {
		event = { name = "BufReadPost", defer = true },
		setup = function(scroll)
			scroll.setup(cfg.scroll or {})
		end,
	})

	-- Window auto-resize + maximize (lazy — needs a second window to be useful)
	packer.lazy("beast.libs.window", {
		event = { name = "WinNew", defer = true },
	   -- stylua: ignore
	 	keys = {
	 		{ "<leader>zz",  function() require("beast.libs.window").maximize() end, desc = "Zoom window", group = "Window" },
	 		{ "<leader>z=", function() require("beast.libs.window").equalize() end, desc = "Equalize windows", group = "Window" },
	 	},
		setup = function(window)
			window.setup(cfg.window or {})
		end,
	})

	-- Autopairs (lazy — install mappings on first InsertEnter)
	packer.lazy("beast.libs.autopairs", {
		event = {
			{
				name = "InsertEnter",
				defer = false,
				cond = function()
					return vim.bo.buftype == "" and vim.api.nvim_buf_get_name(0) ~= ""
				end,
			},
			{ name = "CmdlineEnter", defer = false },
		},
    -- stylua: ignore
		keys = {
			{ "<leader>up", function() require("beast.libs.autopairs").toggle() end, desc = "Toggle autopairs", group = "Autopairs" },
		},
		setup = function(autopairs)
			autopairs.setup(cfg.autopairs or {
				skip_next = [=[[%w%%%'%[%"%.%`%$]]=],
				skip_ts = { "string" },
				skip_unbalanced = true,
				markdown = true,
			})
			autopairs.enable()
		end,
	})

	packer.lazy("beast.libs.key", {
		event = "VimEnter",
		init = function()
			_G.Key = Util.mod("beast.libs.key") ---@type Beast.Key
		end,
		setup = function()
			Key.setup(cfg.key or {})
			Key.safe_set("n", "<leader>d", View.buf.delete, { desc = "Close current buffer", group = "Buffer" })
			Key.safe_set("n", "<leader>n", function()
				require("beast.libs.notify").dismiss()
				require("beast.libs.toast").dismiss()
			end, { desc = "Dismiss all notifications", group = "Notify" })
      -- stylua: ignore
      Key.safe_set("n", "<leader>p", function() require("beast.libs.packer.ui").open() end, { desc = "Open packer UI", group = "Packer" })
		end,
	})

	_G.Lsp = Util.mod("beast.libs.lsp") ---@type Beast.Lsp
	-- LSP infrastructure (eager — must register diagnostics + LspAttach
	-- dispatcher before any FileType autocmd fires, so server `register()`
	-- calls from anywhere downstream resolve correctly).
	Lsp.setup(cfg.lsp or {})
	-- Buffer-local LSP navigation keymaps backed by the finder picker.
	-- Each is gated on the attached client supporting the corresponding method.
	Lsp.on_attach(function(client, bufnr)
		local bind = function(lhs, method, source, desc)
			if not client:supports_method(method) then
				return
			end
			Key.safe_set("n", lhs, function()
				require("beast.libs.finder").open(source)
			end, { buffer = bufnr, desc = desc, group = "LSP" })
		end
		bind("gd", "textDocument/definition", "lsp_definitions", "Goto definition")
		bind("gr", "textDocument/references", "lsp_references", "Goto references")
		bind("gD", "textDocument/declaration", "lsp_declarations", "Goto declaration")
		bind("gi", "textDocument/implementation", "lsp_implementations", "Goto implementation")
	end)

	-- stylua: ignore
	_G.gh = function(x) return "https://github.com/" .. x end

	packer.setup(cfg.packer or {})

	cfg.starter.keys[#cfg.starter.keys + 1] = { verb = "press", key = "<leader>p", desc = "to manage plugins" }
	cfg.starter.keys[#cfg.starter.keys + 1] = { verb = "press", key = "<leader>f", desc = "to find files" }
	-- Starter screen (eager — must register VimEnter autocmd before VimEnter fires)
	require("beast.libs.starter").setup(cfg.starter)
end

return M
