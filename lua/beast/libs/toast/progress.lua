-- LSP progress → toast adapter.
--
-- Subscribes to the LspProgress autocmd (Neovim 0.10+) and shows ONE toast per
-- LSP client, not per token. Servers like basedpyright open a brand new token
-- for every tiny analysis pass (begin("") -> report("1 file to analyze") ->
-- done, all within tens of ms), so a toast per token would flash and stack.
--
--   * The first message of a burst creates the toast immediately.
--   * Repeats of the same message are only counted; the toast is repainted at
--     most once per config.progress.show_delay window, as "<message> (n)".
--     Percentage tokens (lua_ls) are never counted.
--   * Once no token is active and no event arrived for a full window, the
--     toast renders a final ✔ frame and dismisses after config.progress.done_linger
--     ms. A new event during that linger continues the same toast and count.
--
-- Repaints run on a throttled vim.uv timer. The spinner is time-derived (no
-- per-client state).
--
-- Loosely coupled: only uses the public toast API (toast(), toast.update,
-- toast.dismiss_id) — never touches stack/state/ui directly.

local config = require("beast.libs.toast.config")
local toast = require("beast.libs.toast")

local M = {}

---@class Beast.Toast.Progress.Frame
---@field title string
---@field message string
---@field percentage? integer
---@field count integer          consecutive occurrences of `message`
---@field done? boolean          final ✔ frame

---@class Beast.Toast.Progress.Client
---@field id integer
---@field name string
---@field tokens table<string, true>     active token keys
---@field last? Beast.Toast.Progress.Frame  latest content, counted silently
---@field disp? Beast.Toast.Progress.Frame  what is currently painted
---@field record? Beast.Toast.Record
---@field done boolean                   true while the final frame lingers
---@field last_event number              hrtime ms of the last event
---@field next_paint number              hrtime ms before which content is not repainted
---@field dismiss_gen integer            bumped to cancel a pending linger dismiss

---@type table<integer, Beast.Toast.Progress.Client>
local clients = {}

---@type uv.uv_timer_t|nil
local timer = nil
local timer_running = false

-- =============================================================================
-- HELPERS
-- =============================================================================

---@return number
local function now_ms()
	return vim.uv.hrtime() / 1e6
end

---Time-derived spinner frame. No per-entry state.
---@return string
local function spinner()
	local frames = config.progress.spinner
	local interval = config.progress.spinner_interval
	local idx = math.floor(now_ms() / interval) % #frames + 1
	return frames[idx]
end

---Build the segment list for a frame. The plain-text message is derived
---from the segments via table.concat so the two can never drift. The title
---segment is omitted when empty (basedpyright sends `begin("")`); the toast
---itself already carries the client name.
---Shapes:
---  with percentage: "<title>  ⠹  [████░░░░░░░░░░░░░░░░] 42%  <message>"
---  no percentage:   "<title>  ⠹  <message> (n)"      ((n) only when n > 1)
---  done:            "<title>  ✔  <message or 'done'> (n)"
---@param frame Beast.Toast.Progress.Frame
---@return string text
---@return Beast.Toast.Fragment[] segments
local function format_line(frame)
	local msg = frame.message or ""
	local segs = {}

	if frame.title ~= "" then
		segs[#segs + 1] = { text = frame.title, hl = "BeastToastProgressTitle" }
		segs[#segs + 1] = { text = "  " }
	end

	if frame.done then
		segs[#segs + 1] = { text = "✔", hl = "BeastToastProgressDone" }
		segs[#segs + 1] = { text = "  " }
		segs[#segs + 1] = { text = msg ~= "" and msg or "done", hl = "BeastToastProgressMessage" }
	else
		segs[#segs + 1] = { text = spinner(), hl = "BeastToastProgressSpinner" }
		segs[#segs + 1] = { text = "  " }
		if frame.percentage ~= nil then
			local width = config.progress.bar_width
			local pct = math.max(0, math.min(100, frame.percentage))
			local filled = math.floor(pct / 100 * width + 0.5)
			segs[#segs + 1] = { text = "[", hl = "BeastToastProgressBracket" }
			segs[#segs + 1] = { text = string.rep("█", filled), hl = "BeastToastProgressBarDone" }
			segs[#segs + 1] = { text = string.rep("░", width - filled), hl = "BeastToastProgressBarTodo" }
			segs[#segs + 1] = { text = "] ", hl = "BeastToastProgressBracket" }
			segs[#segs + 1] = { text = ("%d%%"):format(pct), hl = "BeastToastProgressPercent" }
			segs[#segs + 1] = { text = "  " }
		end
		segs[#segs + 1] = { text = msg, hl = "BeastToastProgressMessage" }
	end

	if frame.count > 1 and frame.percentage == nil then
		segs[#segs + 1] = { text = (" (%d)"):format(frame.count), hl = "BeastToastProgressCount" }
	end

	local parts = {}
	for i, s in ipairs(segs) do
		parts[i] = s.text
	end
	return table.concat(parts), segs
end

---Repaint a client's toast from `disp`. No-op until the toast exists.
---@param c Beast.Toast.Progress.Client
local function paint(c)
	if not (c.record and c.disp) then
		return
	end
	local text, segs = format_line(c.disp)
	c.record.message = text
	c.record.segments = segs
	toast.update(c.record)
end

---Copy `last` into `disp` (what is on screen) and open the next count window.
---@param c Beast.Toast.Progress.Client
---@param done? boolean
local function flush(c, done)
	c.disp = vim.tbl_extend("force", c.last, { done = done or false })
	c.next_paint = now_ms() + config.progress.show_delay
	paint(c)
end

---Create the client's toast right away (leading edge) once it has content.
---@param c Beast.Toast.Progress.Client
local function show(c)
	if c.record or not c.last then
		return
	end
	c.disp = vim.tbl_extend("force", c.last, { done = false })
	local text, segs = format_line(c.disp)
	local record = toast(text, "INFO", {
		title = c.name,
		timeout = false,
		segments = segs,
	})
	-- toast() returns {} when filtered by level; stay unshown.
	if record and record.id then
		c.record = record
		c.next_paint = now_ms() + config.progress.show_delay
	end
end

-- =============================================================================
-- EVENT HANDLING
-- =============================================================================

---Forward declaration: defined after `tick` below.
local ensure_timer

---Fold an event's content into `last`. Same message as before (and no
---percentage) only bumps the count; anything else starts a new count at 1.
---Events with no title, message or percentage (basedpyright's `begin("")`)
---carry nothing to show and are ignored.
---@param c Beast.Toast.Progress.Client
---@param value lsp.WorkDoneProgressBegin|lsp.WorkDoneProgressReport
local function merge(c, value)
	local msg = value.message or ""
	local title = value.title or ""
	if msg == "" and title == "" and value.percentage == nil then
		return
	end

	local l = c.last
	if l and msg ~= "" and l.message == msg and value.percentage == nil and l.percentage == nil then
		l.count = l.count + 1
		return
	end
	c.last = {
		title = title ~= "" and title or (l and l.title or ""),
		message = msg ~= "" and msg or (l and l.message or ""),
		percentage = value.percentage ~= nil and value.percentage or (l and l.percentage),
		count = 1,
	}
end

---Mark the final frame and dismiss the toast after done_linger.
---@param c Beast.Toast.Progress.Client
local function finish(c)
	c.done = true
	flush(c, true)
	local gen = c.dismiss_gen
	vim.defer_fn(function()
		-- A new event during the linger bumped dismiss_gen: keep the toast.
		if c.dismiss_gen ~= gen or not c.done then
			return
		end
		toast.dismiss_id(c.record.id)
		if clients[c.id] == c then
			clients[c.id] = nil
		end
	end, config.progress.done_linger)
end

---Merge an LSP progress event into its client's state.
---@param client_id integer
---@param params lsp.ProgressParams
local function on_event(client_id, params)
	if not params or not params.token or not params.value then
		return
	end

	local value = params.value
	local key = tostring(params.token)
	local c = clients[client_id]

	if not c then
		local client = vim.lsp.get_client_by_id(client_id)
		-- The autocmd can outlive the client briefly; bail rather than guess a name.
		if not client then
			return
		end
		c = {
			id = client_id,
			name = client.name,
			tokens = {},
			done = false,
			last_event = 0,
			next_paint = 0,
			dismiss_gen = 0,
		}
		clients[client_id] = c
	end

	c.last_event = now_ms()

	if value.kind == "end" then
		c.tokens[key] = nil
	else
		c.tokens[key] = true
		merge(c, value)
		-- New work cancels a pending linger dismiss and continues the same toast.
		if c.done then
			c.next_paint = 0 -- leave the ✔ frame on the next tick
		end
		c.done = false
		c.dismiss_gen = c.dismiss_gen + 1
		show(c)
	end

	ensure_timer()
end

-- =============================================================================
-- TIMER LOOP
-- =============================================================================

---Throttled frame, per client:
---  * promote to the final ✔ frame after a full quiet window with no token
---  * repaint changed content at most once per window
---  * keep the spinner moving while a token is active
local function tick()
	local active = false
	local now = now_ms()
	local window = config.progress.show_delay

	for id, c in pairs(clients) do
		if not vim.lsp.get_client_by_id(c.id) then
			if c.record then
				toast.dismiss_id(c.record.id)
			end
			c.dismiss_gen = c.dismiss_gen + 1
			clients[id] = nil
		elseif not c.record then
			-- Nothing worth showing (e.g. only empty begin/end): forget it.
			if next(c.tokens) == nil then
				clients[id] = nil
			else
				active = true
			end
		elseif not c.done then
			active = true
			if next(c.tokens) == nil and now - c.last_event >= window then
				finish(c)
			elseif now >= c.next_paint and not vim.deep_equal(c.disp, vim.tbl_extend("force", c.last, { done = false })) then
				flush(c)
			elseif next(c.tokens) ~= nil then
				paint(c)
			end
		end
	end

	if not active then
		if timer then
			timer:stop()
		end
		timer_running = false
	end
end

---Start the throttled redraw timer if not already running. Idempotent.
function ensure_timer()
	if timer_running then
		return
	end
	if not timer then
		timer = vim.uv.new_timer()
	end
	timer:start(config.progress.throttle, config.progress.throttle, vim.schedule_wrap(tick))
	timer_running = true
end

-- =============================================================================
-- SETUP
-- =============================================================================

function M.setup()
	local group = vim.api.nvim_create_augroup("beast_toast_progress", { clear = true })
	vim.api.nvim_create_autocmd("LspProgress", {
		group = group,
		callback = function(event)
			local data = event.data or {}
			local client_id, params = data.client_id, data.params
			-- Defer through the main loop so toast() can build the float
			-- safely (it returns nil in fast-event / vim_starting paths).
			if vim.in_fast_event() or vim.fn.has("vim_starting") == 1 then
				vim.schedule(function()
					on_event(client_id, params)
				end)
			else
				on_event(client_id, params)
			end
		end,
	})
end

-- Exposed for tests.
M._clients = clients

return M
