-- Claude Code connection + activity, as reported by beast.libs.review.
--
-- The review lib hosts the loopback WebSocket server Claude Code connects to,
-- so it already knows everything this component needs. Only two states are
-- visible:
--
--   idle     Claude connected, nothing in flight
--   running  Claude connected, one or more proposed diffs awaiting the user
--
-- Anything else (review server not running, no client connected) renders
-- nothing. A dimmed "not connected" badge was rejected: the bar should say
-- something only when there is something to say.
--
-- `running` is keyed off openDiff calls, not message timestamps: each openDiff
-- blocks a Claude Code request until the user decides, so a non-zero pending
-- count is real in-flight work. Timestamps were rejected as the signal -
-- they cannot distinguish "wrote one message" from "is actively running".
--
-- The review lib is lazy-loaded (VimEnter, only when review.enabled), so this
-- provider must never assume it is loaded: `package.loaded` is checked first,
-- and the component reacts to `BeastReviewStatusChanged`, which only fires
-- once that lib is live.
--
-- Claude's brand color, deliberately a literal rather than a palette alias: the
-- badge identifies the tool, so it should not shift with the colorscheme the
-- way the surrounding statusline does.
local CLAUDE_FG = "#D97757"

--- Connection state and pending-diff count. Returns nil when nothing should be
--- displayed (server down, or no client attached).
---@return "idle"|"running"|nil state
---@return integer pending
local function state_and_counts()
  -- stylua: ignore
  if not package.loaded["beast.libs.review"] then return nil, 0 end

	local ok, status = pcall(function()
		return require("beast.libs.review").status()
	end)
  -- stylua: ignore
  if not ok or type(status) ~= "table" then return nil, 0 end

  -- stylua: ignore
  if not status.running or (status.clients or 0) == 0 then return nil, 0 end

	local pending = status.pending or 0
	return pending > 0 and "running" or "idle", pending
end

---@type Beast.Statusline.ComponentSpec
return {
	update = { "User BeastReviewStatusChanged" },
	scope = "global",
	-- Low: a connection badge is the first thing worth dropping when the bar
	-- runs out of room.
	priority = 30,
	provider = function()
		local state, pending = state_and_counts()
    -- stylua: ignore
    if not state then return {} end

		local icon = (Icon and Icon.claude) or "󰚩 "
		-- State is carried by weight alone: the color is always the brand, so
		-- the badge reads as "Claude" regardless of what it is doing.
		local hl = { fg = CLAUDE_FG, bold = state == "running" or nil }

		-- The count rides inside the icon's fragment so the number reads as
		-- part of the badge.
		return { { text = pending > 0 and (icon .. pending) or icon, hl = hl } }
	end,
}
