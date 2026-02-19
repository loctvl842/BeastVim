local M = {}
local cfg

function M.defaults()
  return {
    border = "rounded",
    width = 0.85,
    height = 0.7,
    backdrop_blend = 30,
    keymaps = {
      close = { "q", "<Esc>" },
    }
  }
end

M.opts = {
  border = "rounded",
}

local function create_float()
  local width = math.floor(vim.o.columns * 0.85)
  local height = math.floor(vim.o.lines * 0.7)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- ==========================================================================
  -- Backdrop
  -- ==========================================================================
  local backdrop_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[backdrop_buf].buftype = "nofile"
  vim.bo[backdrop_buf].bufhidden = "wipe"

  local backdrop_win = vim.api.nvim_open_win(backdrop_buf, false, {
    relative = "editor",
    row = 0,
    col = 0,
    width = vim.o.columns,
    height = vim.o.lines,
    style = "minimal",
    focusable = false,
    zindex = 1,
  })
  vim.wo[backdrop_win].winblend = M.opts.backdrop_blend or 30

  -- ==========================================================================
  -- Main floating window
  -- ==========================================================================
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = M.opts.border or "rounded",
    zindex = 2,
  })

  return buf
end

function M.open()
  local buf = create_float()
end

function M.setup(opts)
  cfg = vim.tbl_deep_extend("force", M.defaults(), opts or {})
  -- do module wiring with cfg (keymaps, state, etc.)
end

function M.get()
  return cfg or M.defaults()
end

return M
