-- =========================================================================
-- Manual test: Beast key hint (press-and-wait)
-- =========================================================================
-- Open the BeastVim config root, then inside Neovim run:
--   :luafile tests/test-key-hint.lua
--
-- Then manually verify:
--   1. Press <leader>           → hint appears bottom-right with `f` entry
--   2. Press <leader>f          → hint updates, breadcrumb shows " <space> f "
--   3. Press <leader>ff         → echoes "find files" via vim.notify
--   4. Press <leader> then <Esc>→ hint closes, no side-effect
--   5. Press <leader> then <BS> → hint stays at root level
--   6. Press <leader>x          → hint closes, no echo (x not mapped)
--   7. Add triggers {"g","f"} and map `gf`; pressing `g` then `f` must resolve
--      to `gf` once (the `f` trigger must not open a second hint while the
--      first hint UI is active/resolving).
-- =========================================================================

local Key = require("beast.libs.key")

-- Register six sample maps under <leader>f
local function notify(msg)
	return function()
		vim.notify("[test] " .. msg, vim.log.levels.INFO)
	end
end

-- Group label (no rhs)
Key.safe_set("n", "<leader>f", function() end, { group = "file" })

Key.safe_set("n", "<leader>ff", notify("find files"), { desc = "Find files" })
Key.safe_set("n", "<leader>fg", notify("live grep"), { desc = "Live grep" })
Key.safe_set("n", "<leader>fr", notify("recent files"), { desc = "Recent files" })
Key.safe_set("n", "<leader>fb", notify("buffers"), { desc = "Buffers" })
Key.safe_set("n", "<leader>fn", notify("new file"), { desc = "New file" })
Key.safe_set("n", "<leader>fs", notify("save file"), { desc = "Save file" })

-- Enable hint (idempotent — safe even if Key.setup already ran).
Key.setup({ hint = { enabled = true } })

vim.notify("Beast key hint test ready — press <leader> to begin.", vim.log.levels.INFO)
