local M = {}

local hl = require("beast.setup.highlights")
M.highlight_modules = hl.highlight_modules
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
---@field starter? Beast.Starter.Config
---@field window? Beast.Window.Config
---@field lsp? Beast.LSP.Config
local defaults = {
	key = {},
	notify = {},
	toast = {},
	explorer = {},
	packer = {},
	treesitter = {},
	starter = {},
}

---@param opts? Beast.Config
function M.setup(opts)
	local user_starter_keys = opts and opts.starter and opts.starter.keys
	local cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
	-- Opt-in: only render the BeastVim key rows when the user explicitly
	-- provided `starter.keys`. Otherwise fall through to the bare native intro.
	if user_starter_keys == nil then
		cfg.starter.keys = {}
	end

	require("beast.setup.globals").run()

	hl.setup()

	Key.setup(cfg.key)

	Key.safe_set("n", "<leader>d", View.buf.delete, { desc = "Close current buffer", group = "Buffer" })

	-- Notification
	local notify = require("beast.libs.notify")
	notify.setup(cfg.notify)
	local toast = require("beast.libs.toast")
	toast.setup(cfg.toast)
	_G.Toast = toast

	Key.safe_set("n", "<leader>n", function()
		notify.dismiss()
		toast.dismiss()
	end, { desc = "Dismiss all notifications", group = "Notify" })

	require("beast.libs.confirm").setup()

	-- LSP infrastructure (eager — must register diagnostics + LspAttach
	-- dispatcher before any FileType autocmd fires, so server `register()`
	-- calls from anywhere downstream resolve correctly).
	Lsp.setup(cfg.lsp or {})

	local packer = require("beast.libs.packer")

	-- stylua: ignore
	_G.gh = function(x) return "https://github.com/" .. x end
	---@type Beast.Packer.Config
	packer.setup(cfg.packer)
  -- stylua: ignore
	Key.safe_set("n", "<leader>p", function() require("beast.libs.packer.ui").open() end, { desc = "Open packer UI", group = "Packer" })
	cfg.starter.keys[#cfg.starter.keys + 1] = { verb = "press", key = "<leader>p", desc = "to manage plugins" }

	-- Statusline (declarative components, native %! evaluation)
	local stl = require("beast.libs.statusline")
	local cpn = require("beast.libs.statusline.components")
	stl.setup({
		left = { cpn.git_branch, cpn.diagnostics },
		right = { cpn.macro, cpn.git_commit, cpn.position, cpn.filetype, cpn.shiftwidth, cpn.encoding, cpn.mode },
	})

	-- Breadcrumb / winbar (lazy — deferred past first screen update)
	packer.lazy("beast.libs.breadcrumb", {
		event = { name = "BufEnter", defer = true },
		setup = function(breadcrumb)
			breadcrumb.setup(cfg.breadcrumb or {})
		end,
	})

	-- Breadcrumb / winbar (lazy — deferred past first screen update)
	packer.lazy("beast.libs.breadcrumb", {
		event = { name = "BufEnter", defer = true },
		setup = function(breadcrumb)
			breadcrumb.setup(cfg.breadcrumb or {})
		end,
	})

	-- Tabline (lazy — deferred past first screen update)
	packer.lazy("beast.libs.tabline", {
		event = { name = "VimEnter", defer = true },
    -- stylua: ignore
		keys = {
			{ "[B", function() require("beast.libs.tabline").move_prev() end, mode = "n", desc = "Move buffer prev", group = "Tabline" },
      { "]B", function() require("beast.libs.tabline").move_next() end, mode = "n", desc = "Move buffer next", group = "Tabline" },
		},
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
		event = { name = "VimEnter", defer = true },
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
		event = { name = "VimEnter", defer = true },
		setup = function(explorer)
			explorer.setup(cfg.explorer)
			-- Detect directory buffers from startup (e.g. `nvim ~/Downloads`),
			-- capture the path and wipe the buffer before opening the explorer.
			for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				local name = vim.api.nvim_buf_get_name(buf)
				if name ~= "" and vim.fn.isdirectory(name) == 1 then
					local dir = vim.fn.fnamemodify(name, ":p"):gsub("/$", "")
					pcall(vim.api.nvim_buf_delete, buf, { force = true })
					explorer.open(dir)
					return
				end
			end
			-- -- No directory buffer found — auto-open when nvim started with no file
			-- if vim.fn.argc() == 0 and vim.api.nvim_buf_get_name(0) == "" then
			-- 	explorer.open()
			-- end
		end,
	})

	-- Indent scope indicator (lazy — activate on first buffer with content)
	packer.lazy("beast.libs.indent", {
		event = { name = "BufReadPost", defer = true },
		setup = function(indent)
			indent.setup(cfg.indent or {})
		end,
	})

	-- Treesitter (lazy — enable builtin highlighting + fold on FileType)
	packer.lazy("beast.libs.treesitter", {
		event = { name = "FileType", defer = true },
		setup = function(ts)
			ts.setup(cfg.treesitter)
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
				"<leader>C",
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
	cfg.starter.keys[#cfg.starter.keys + 1] = { verb = "press", key = "<leader>f", desc = "to find files" }

	-- Starter screen (eager — must register VimEnter autocmd before VimEnter fires)
	require("beast.libs.starter").setup(cfg.starter)

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

	-- Initial palette extraction (colorscheme should be loaded by packer)
	Palette.refresh()
	M.reload_highlights()
end

return M
