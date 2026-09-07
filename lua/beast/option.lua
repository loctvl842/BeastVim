vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
-- Cap matchparen search time (default 300ms). On large files the bracket-match
-- scan fires every CursorMoved and can stall the editor. 100ms / 30ms keeps
-- highlighting responsive without blocking input.
vim.g.matchparen_timeout = 100
vim.g.matchparen_insert_timeout = 30

-- Over SSH there is no local X11/Wayland display for xclip/xsel/wl-copy to
-- attach to, so `unnamedplus` alone can't reach the client's clipboard. OSC52
-- pipes the clipboard contents through the terminal escape sequence instead,
-- which works over plain SSH as long as the terminal honors it.
--
-- Paste is intentionally NOT wired to OSC52's query sequence: most terminals
-- (including Windows Terminal) refuse to answer it for security reasons
-- (it would let a remote shell silently read the local clipboard), so
-- vim.ui.clipboard.osc52's paste() just hangs for ~10s before giving up.
--
-- Neovim calls the provider's paste() on every read of "+" (and of the
-- unnamed register, via 'clipboard = "unnamedplus"'), then overwrites the
-- internal register with whatever it returns. A paste() that always answers
-- "" would therefore clobber every yank/delete done in this session, and 'p'
-- after 'y'/'d'/'x' would fail with E353. So paste() instead serves the last
-- value this session copied - same-session yank/paste keeps working. Only
-- pasting text that was copied outside this session still needs the
-- terminal's native paste (e.g. Ctrl+Shift+V), which injects the text via
-- bracketed paste and needs no clipboard provider at all.
---@return boolean
if vim.env.SSH_TTY and (vim.env.DISPLAY or "") == "" and (vim.env.WAYLAND_DISPLAY or "") == "" then
	local osc52 = require("vim.ui.clipboard.osc52")
	-- Last (lines, regtype) this session sent through OSC52 copy. regtype is
	-- "" while nothing has been copied yet, and is kept alongside lines so
	-- linewise/charwise/blockwise pastes round-trip correctly.
	local last_copied = { lines = { "" }, regtype = "" }

	local function copy_with_cache(reg)
		local osc_copy = osc52.copy(reg)
		return function(lines, regtype)
			last_copied = { lines = lines, regtype = regtype }
			osc_copy(lines, regtype)
		end
	end

	local function paste_from_cache()
		if last_copied.regtype ~= "" then
			return { last_copied.lines, last_copied.regtype }
		end

		vim.notify("Paste from system clipboard over SSH: use the terminal's native paste (Ctrl+Shift+V).", vim.log.levels.WARN)
		return { "" }
	end

	vim.g.clipboard = {
		name = "OSC 52",
		copy = {
			["+"] = copy_with_cache("+"),
			["*"] = copy_with_cache("*"),
		},
		paste = {
			["+"] = paste_from_cache,
			["*"] = paste_from_cache,
		},
	}
end

local o = vim.opt
-- stylua: ignore start
o.backup            = false                             -- creates a backup file
o.clipboard         = "unnamedplus"                     -- allows neovim to access the system clipboard
o.cmdheight         = 0                                 -- more space in the neovim command line for displaying messages
o.confirm           = true                              -- Confirm to save changes before exiting modified buffer
o.completeopt       = { "menu", "menuone", "noselect" } -- mostly just for cmp
o.conceallevel      = 0                                 -- so that `` is visible in markdown files
o.fileencoding      = "utf-8"                           -- the encoding written to a file
o.incsearch         = true
o.hlsearch          = true                              -- highlight all matches on previous search pattern
o.inccommand        = "nosplit"
o.ignorecase        = true                              -- ignore case in search patterns
o.grepformat        = "%f:%l:%c:%m"
o.grepprg           = "rg --vimgrep"
o.mouse             = "a"                               -- allow the mouse to be used in neovim
o.pumheight         = 10                                -- pop up menu height
o.showmode          = false                             -- we don't need to see things like -- INSERT -- anymore
-- o.smartcase    = true                                 -- smart case
o.smartindent       = true                              -- make indenting smarter again
o.splitbelow        = true                              -- force all horizontal splits to go below current window
o.splitright        = true                              -- force all vertical splits to go to the right of current window
o.swapfile          = false                             -- creates a swapfile
o.termguicolors     = true                              -- set term gui colors (most terminals support this)
o.timeoutlen        = vim.g.vscode and 1000 or 200      -- Lower than default (1000) to quickly trigger key hint
-- o.undofile          = true                              -- enable persistent undo
o.updatetime        = 500                               -- faster completion (4000ms default)
o.fixendofline      = false                             -- Always add newline at end of file
o.wildmode          = "longest:full,full"               -- Command-line completion mode
o.writebackup       = false                             -- if a file is being edited by another program (or was written to file while editing with another program), it is not allowed to be edited
o.expandtab         = true                              -- convert tabs to spaces
o.shiftwidth        = 2                                 -- the number of spaces inserted for each indentation
o.tabstop           = 2                                 -- insert 2 spaces for a tab
o.cursorline        = true                              -- highlight the current line
o.relativenumber    = false                             -- set relative numbered lines
o.numberwidth       = 4                                 -- set number column width to 2 {default 4}
o.wrap              = false                             -- display lines as one long line
o.sidescrolloff     = 0
o.scrolloff         = 4
o.smoothscroll      = true
o.laststatus        = 3
o.list              = true                              -- Show some invisible characters (tabs...
o.guicursor         = "n-v-c-sm:block,i-ci-ve:ver25,r-cr-o:hor20"
-- o.guicursor         = "a:xxx"
o.background        = "dark"
o.selection         = "exclusive"
o.virtualedit       = "onemore"
o.showcmd           = false
o.title             = true
o.titlestring       = "%<%F %= - BeastVim"
o.mousemoveevent    = true
o.syntax            = "off"
o.spelllang         = { "en", "vi" }
o.fillchars = {
  foldopen = "",
  foldclose = "",
  fold = " ",
  foldsep = " ",
  diff = "╱",
  eob = " ",
}
o.formatoptions = "jcroqlnt" -- tcqj
o.grepformat = "%f:%l:%c:%m"
-- session
o.sessionoptions = { "buffers", "curdir", "tabpages", "winsize", "help", "globals", "skiprtp", "folds" }

o.shortmess:append("c")
o.viewoptions:remove("curdir") -- disable saving current directory with views

-- vim.opt.listchars:append "space:⋅"
-- vim.opt.listchars:append "eol:↴"
o.listchars = {
  tab   = "  ", -- Make tabs invisible (two spaces)
  trail = "-",  -- Keep your trailing space marker
  nbsp  = "+",  -- Keep your non-breaking space marker
}

vim.cmd("set whichwrap+=<,>,[,]")
vim.cmd([[set iskeyword+=-]])
-- diable open fold with `l`
vim.cmd([[set foldopen-=hor]])

-- Window auto-resize defaults (consumed by beast.libs.window's autowidth)
o.winwidth          = 30
o.winminwidth       = 10
o.equalalways       = true
