local M = {}

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
local defaults = {
	key = {},
	notify = {},
	toast = {},
	explorer = {},
	packer = {},
	treesitter = {},
}

---@param opts? Beast.Config
function M.setup(opts)
	local cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

	require("beast.option")

	_G.Util = require("beast.util")
	_G.Palette = require("beast.palette")
	_G.Key = require("beast.libs.key")
	_G.Buffer = require("beast.libs.buf")
	_G.Icon = require("beast.icon")

	Palette.setup()

	-- Refresh palette + reload all Beast highlights on colorscheme change
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("BeastPalette", { clear = true }),
		callback = function()
			vim.schedule(function()
				Palette.refresh()
				M.reload_highlights()
			end)
		end,
	})

	Key.setup(cfg.key)

	Key.safe_set("n", "<leader>d", Buffer.delete, { desc = "Close current buffer", group = "Buffer" })

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

	local packer = require("beast.libs.packer")

	-- stylua: ignore
	_G.gh = function(x) return "https://github.com/" .. x end
	---@type Beast.Packer.Config
	packer.setup(cfg.packer)
	Key.safe_set("n", "<leader>p", function()
		require("beast.libs.packer.ui").open()
	end)

	-- Statusline (declarative components, native %! evaluation)
	local stl = require("beast.libs.statusline")
	local cpn = require("beast.libs.statusline.components")
	stl.setup({
		left = { cpn.git_branch, cpn.diagnostics },
		right = { cpn.git_commit, cpn.position, cpn.filetype, cpn.shiftwidth, cpn.encoding, cpn.mode },
	})

	-- Breadcrumb / winbar (lazy — deferred past first screen update)
	packer.lazy("beast.libs.breadcrumb", {
		event = "BufEnter",
		defer = true,
		setup = function(breadcrumb)
			breadcrumb.setup(cfg.breadcrumb or {})
		end,
	})

	-- Tabline (lazy — deferred past first screen update)
	packer.lazy("beast.libs.tabline", {
		event = "VimEnter",
		defer = true,
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
  -- stylua: ignore start
	Key.safe_set("n", "[B", function() require("beast.libs.tabline").move_prev() end, { desc = "Move buffer prev", group = "Tabline" })
	Key.safe_set("n", "]B", function() require("beast.libs.tabline").move_next() end, { desc = "Move buffer next", group = "Tabline" })
	-- stylua: ignore end

	-- Statuscolumn (lazy — deferred past first screen update)
	packer.lazy("beast.libs.statuscolumn", {
		event = "VimEnter",
		defer = true,
		setup = function(stc)
			stc.setup({})
		end,
	})
	-- Git (lazy — attaches per buffer on BufReadPost)
	packer.lazy("beast.libs.git", {
		event = "BufReadPost",
		defer = true,
		setup = function(g)
			g.setup({})
		end,
	})
  -- stylua: ignore start
  Key.safe_set("n", "<leader>gp", function() require("beast.libs.git").preview_hunk() end, {desc = "Preview current hunk", group = "Git"})
  Key.safe_set("x", "<leader>gp", function()
    local s = vim.fn.line("v")
    local e = vim.fn.line(".")
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
    require("beast.libs.git").preview_hunk_range(s, e)
  end, {desc = "Preview hunks in selection", group = "Git"})
  Key.safe_set("n", "]c", function() require("beast.libs.git").next_hunk() end, {desc = "Next hunk", group = "Git"})
  Key.safe_set("n", "[c", function() require("beast.libs.git").prev_hunk() end, {desc = "Previous hunk", group = "Git"})
	-- stylua: ignore end

	vim.g.loaded_netrw = 1
	vim.g.loaded_netrwPlugin = 1
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
		event = "VimEnter",
		defer = true,
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
		event = "BufReadPost",
		defer = true,
		setup = function(indent)
			indent.setup(cfg.indent or {})
		end,
	})

	-- Treesitter (lazy — enable builtin highlighting + fold on FileType)
	packer.lazy("beast.libs.treesitter", {
		event = "FileType",
		defer = true,
		setup = function(ts)
			ts.setup(cfg.treesitter)
			ts.enable()
		end,
	})

	packer.lazy("beast.libs.finder", {
		defer = true,
		setup = function(finder)
			finder.setup(cfg.finder or {})
		end,
    -- stylua: ignore
		keys = {
			{ "<leader>f", function() require("beast.libs.finder").open("files") end, desc = "Find files" },
			{ "<leader>b", function() require("beast.libs.finder").open("buffers") end, desc = "Find buffers" },
			{ "<leader>/", function() require("beast.libs.finder").open("live_grep") end, desc = "Live grep" },
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
		event = "BufReadPost",
		defer = true,
		setup = function(scroll)
			scroll.setup(cfg.scroll or {})
		end,
	})

	-- Initial palette extraction (colorscheme should be loaded by packer)
	Palette.refresh()
	M.reload_highlights()
end

--- Registry of highlight modules to reload on ColorScheme change.
--- Lazy-loaded libs register their highlights dynamically via packer.lazy().
---@type string[]
M.highlight_modules = {
	"beast.palette.highlights",
	"beast.libs.confirm.highlights",
	"beast.libs.explorer.highlights",
	"beast.libs.finder.highlights",
	"beast.libs.key.highlights",
	"beast.libs.notify.highlights",
	"beast.libs.packer.highlights",
	"beast.libs.statusline.highlights",
	"beast.libs.statuscolumn.highlights",
	"beast.libs.git.highlights",
	"beast.libs.breadcrumb.highlights",
	"beast.libs.tabline.highlights",
	"beast.libs.toast.highlights",
	"beast.libs.indent.highlights",
}

--- Highlight modules that are only needed for builtin colorschemes
--- (third-party schemes define their own treesitter highlights).
---@type table<string, boolean>
local builtin_only_highlights = {
	["beast.libs.treesitter.highlights"] = true,
}

--- Reload all Beast lib highlights.
--- Skips modules whose parent lib hasn't been loaded yet.
--- Skips treesitter highlights for third-party colorschemes.
function M.reload_highlights()
	local is_builtin = Palette.is_builtin_colorscheme()
	for _, mod_name in ipairs(M.highlight_modules) do
		-- stylua: ignore
		if not is_builtin and builtin_only_highlights[mod_name] then goto continue end
		local parent = mod_name:gsub("%.highlights$", "")
		-- stylua: ignore
		if not package.loaded[parent] then goto continue end
		package.loaded[mod_name] = nil
		pcall(require, mod_name)
		::continue::
	end
end

return M
