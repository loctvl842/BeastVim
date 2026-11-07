local config = require("beast.libs.tabline.config")
local truncate = require("beast.libs.tabline.truncate")

local M = {}

local displaywidth = truncate.displaywidth

--- The PID never changes for the lifetime of the process, so resolve it once.
---@type string|nil
local cached_pid

---@return string
local function pid_text()
  if not cached_pid then
    cached_pid = tostring(vim.fn.getpid())
  end
  return cached_pid
end

--- Compute the display width of the PID section.
---@return integer
function M.width()
  -- Renders as " <label_prefix><pid> " = 1 + prefix + pid + 1
  return 1 + displaywidth(config.show_pid_prefix) + displaywidth(pid_text()) + 1
end

--- Render the PID section (right-most tabline item).
---@return string
function M.render()
  return "%#BeastTLPid#" .. " " .. config.show_pid_prefix .. pid_text() .. " "
end

return M
