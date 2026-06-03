-- =========================================================================
-- Manual test: Beast key popup (press-and-wait)
-- =========================================================================
-- Open the BeastVim config root, then inside Neovim run:
--   :luafile tests/test-key-popup.lua
--
-- Then manually verify:
--   1. Press <leader>           → popup appears bottom-right with `f` entry
--   2. Press <leader>f          → popup updates, breadcrumb shows " <space> f "
--   3. Press <leader>ff         → echoes "find files" via vim.notify
--   4. Press <leader> then <Esc>→ popup closes, no side-effect
--   5. Press <leader> then <BS> → popup stays at root level
--   6. Press <leader>x          → popup closes, no echo (x not mapped)
-- =========================================================================

local Key = require("beast.libs.key")

-- Register six sample maps under <leader>f
local function notify(msg)
	return function()
		vim.notify("[test] " .. msg, vim.log.levels.INFO)
	end
end

-- Group label (no rhs)
Key.safe_set("n", "<leader>f", nil, { group = "file" })

Key.safe_set("n", "<leader>ff", notify("find files"), { desc = "Find files" })
Key.safe_set("n", "<leader>fg", notify("live grep"), { desc = "Live grep" })
Key.safe_set("n", "<leader>fr", notify("recent files"), { desc = "Recent files" })
Key.safe_set("n", "<leader>fb", notify("buffers"), { desc = "Buffers" })
Key.safe_set("n", "<leader>fn", notify("new file"), { desc = "New file" })
Key.safe_set("n", "<leader>fs", notify("save file"), { desc = "Save file" })

-- Enable popup (idempotent — safe even if Key.setup already ran).
Key.setup({ popup = { enabled = true } })

vim.notify("Beast key popup test ready — press <leader> to begin.", vim.log.levels.INFO)
