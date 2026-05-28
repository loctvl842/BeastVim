local map = require("beast.libs.key.core")

-------------------- General Mappings --------------------------
map("n", "<leader>w", "<cmd>w!<CR>", { desc = "Save file", group = "General" })
map("n", "<leader>q", "<cmd>q!<CR>", { desc = "Quit window", group = "General" })
map("n", "<leader>Q", "<cmd>qa!<CR>", { desc = "Quit all", group = "General" })

-------------------- Better window navigation ------------------
map("n", "<C-h>", "<C-w>h", { desc = "Go to left window", remap = true, group = "Windows" })
map("n", "<C-j>", "<C-w>j", { desc = "Go to lower window", remap = true, group = "Windows" })
map("n", "<C-k>", "<C-w>k", { desc = "Go to upper window", remap = true, group = "Windows" })
map("n", "<C-l>", "<C-w>l", { desc = "Go to right window", remap = true, group = "Windows" })

-------------------- Buffers -----------------------------------
-- stylua: ignore start
map("n", "<S-h>",   "<cmd>bprevious<cr>", { desc = "Previous buffer", group = "Buffers" })
map("n", "<S-l>",   "<cmd>bnext<cr>",     { desc = "Next buffer", group = "Buffers" })
map("n", "[b",      "<cmd>bprevious<cr>", { desc = "Previous buffer", group = "Buffers" })
map("n", "]b",      "<cmd>bnext<cr>",     { desc = "Next buffer", group = "Buffers" })
map("n", "<C-Tab>", "<cmd>e #<cr>",       { desc = "Switch to alternate buffer", group = "Buffers" })
-- map("n", "<leader>d", function() Util.buf.delete() end, { desc = "Close buffer", group = "Buffers" })
-- stylua: ignore end

-------------------- Press jk fast to enter --------------------
map("i", "jk", "<ESC>", { desc = "Escape insert mode", group = "Insert" })
map("i", "Jk", "<ESC>", { desc = "Escape insert mode", group = "Insert" })
map("i", "jK", "<ESC>", { desc = "Escape insert mode", group = "Insert" })

-------------------- Stay in indent mode -----------------------
map("v", "<", "<gv", { desc = "Indent left (keep selection)", group = "Indent" })
map("v", ">", ">gv", { desc = "Indent right (keep selection)", group = "Indent" })
map("v", "p", '"_dP', { desc = "Paste without yanking selection", group = "Indent" })

-------------------- Resize windows ----------------------------
-- stylua: ignore start
map("n", "<C-Up>",    "<cmd>resize +2<cr>",           { desc = "Increase window height", group = "Windows" })
map("n", "<C-Down>",  "<cmd>resize -2<cr>",           { desc = "Decrease window height", group = "Windows" })
map("n", "<C-Left>",  "<cmd>vertical resize -2<cr>",  { desc = "Decrease window width", group = "Windows" })
map("n", "<C-Right>", "<cmd>vertical resize +2<cr>",  { desc = "Increase window width", group = "Windows" })
-- stylua: ignore end

-------------------- Move text up/ down ------------------------
-- Normal --
map("n", "<A-S-j>", "<cmd>m .+1<cr>==", { desc = "Move line down", group = "Move" })
map("n", "<A-S-k>", "<cmd>m .-2<cr>==", { desc = "Move line up", group = "Move" })
-- Block (visual select) --
map("x", "<A-S-j>", ":move '>+1<CR>gv-gv", { desc = "Move selection down", group = "Move" })
map("x", "<A-S-k>", ":move '<-2<CR>gv-gv", { desc = "Move selection up", group = "Move" })
-- Insert --
map("i", "<A-S-j>", "<esc><cmd>m .+1<cr>==gi", { desc = "Move line down", group = "Move" })
map("i", "<A-S-k>", "<esc><cmd>m .-2<cr>==gi", { desc = "Move line up", group = "Move" })
-- Visual --
map("v", "<A-S-j>", ":m '>+1<cr>gv=gv", { desc = "Move selection down", group = "Move" })
map("v", "<A-S-k>", ":m '<-2<cr>gv=gv", { desc = "Move selection up", group = "Move" })

-------------------- No highlight ------------------------------
map("n", ";", ":noh<CR>", { desc = "Clear search highlight", group = "Search" })

-------------------- Inspect -----------------------------------
map("n", "<F2>", "<cmd>Inspect<CR>", { desc = "Inspect highlight group", group = "Inspect" })

-------------------- Split window ------------------------------
map("n", "<leader>\\", ":vsplit<CR>", { desc = "Split window vertically", group = "Windows" })
map("n", "<leader>/", ":split<CR>", { desc = "Split window horizontally", group = "Windows" })

-------------------- Switch two windows ------------------------
map("n", "<A-o>", "<C-w>r", { desc = "Rotate windows", group = "Windows" })

------------------- Select all ---------------------------------
map("n", "<C-a>", "gg<S-v>G", { desc = "Select all", group = "Edit" })

----------------- HACK: Toggle pin scrolloff -------------------
-- stylua: ignore
map("n", "<leader>to", function() vim.opt.scrolloff = 999 - vim.o.scrolloff end, { desc = "Toggle pinned scrolloff", group = "Scroll" })

------------------- Escape behaviors ---------------------------
map({ "i", "n", "s" }, "<esc>", function()
	vim.cmd("noh")
	return "<esc>"
end, { expr = true, desc = "Escape and clear search highlight", group = "General" })
