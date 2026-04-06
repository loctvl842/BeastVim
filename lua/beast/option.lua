vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

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
o.showtabline       = 2                                 -- always show tabs
-- o.smartcase    = true                                 -- smart case
o.smartindent       = true                              -- make indenting smarter again
o.splitbelow        = true                              -- force all horizontal splits to go below current window
o.splitright        = true                              -- force all vertical splits to go to the right of current window
o.swapfile          = false                             -- creates a swapfile
o.termguicolors     = true                              -- set term gui colors (most terminals support this)
o.timeoutlen        = vim.g.vscode and 1000 or 100      -- Lower than default (1000) to quickly trigger which-key
-- o.undofile          = true                              -- enable persistent undo
o.updatetime        = 500                               -- faster completion (4000ms default)
o.fixendofline      = false                             -- Always add newline at end of file
o.wildmode          = "longest:full,full"               -- Command-line completion mode
o.writebackup       = false                             -- if a file is being edited by another program (or was written to file while editing with another program), it is not allowed to be edited
o.expandtab         = true                              -- convert tabs to spaces
o.shiftwidth        = 2                                 -- the number of spaces inserted for each indentation
o.tabstop           = 2                                 -- insert 2 spaces for a tab
o.cursorline        = true                              -- highlight the current line
o.number            = true                              -- set numbered lines
o.relativenumber    = false                             -- set relative numbered lines
o.numberwidth       = 4                                 -- set number column width to 2 {default 4}
o.signcolumn        = "yes"                             -- always show the sign column, otherwise it would shift the text each time
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
-- use fold
o.foldlevel         = 99
o.foldmethod        = "indent"
o.foldenable        = true
o.foldcolumn        = "1"
o.fillchars = {
  foldopen = "",
  foldclose = "",
  fold = " ",
  foldsep = " ",
  diff = "╱",
  eob = " ",
}
o.formatexpr = "v:lua.require'beastvim.util'.format.formatexpr()"
o.formatoptions = "jcroqlnt" -- tcqj
o.grepformat = "%f:%l:%c:%m"
-- session
o.sessionoptions = { "buffers", "curdir", "tabpages", "winsize" }

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
