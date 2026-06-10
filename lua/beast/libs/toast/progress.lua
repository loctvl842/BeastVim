-- LSP progress → toast adapter.
--
-- Subscribes to the LspProgress autocmd (Neovim 0.10+), coalesces events per
-- (client_id, token) into a single sticky toast, and re-renders all active
-- tokens on a throttled vim.uv timer. Each progress event mutates the
-- cached Record; the timer calls toast.update(record) to repaint.
--
-- One token = one toast. Spinner is time-derived (no per-token state).
-- On kind=="end", the toast renders a final ✔ frame and dismisses after
-- config.progress.done_linger ms.
--
-- Loosely coupled: only uses the public toast API (toast(), toast.update,
-- toast.dismiss_id) — never touches stack/state/ui directly.

local config = require("beast.libs.toast.config")
local toast = require("beast.libs.toast")

local M = {}

---@class Beast.Toast.Progress.Entry
---@field record Beast.Toast.Record
---@field client_id integer
---@field client_name string
---@field title string
---@field message string
---@field percentage? integer
---@field kind string                "begin" | "report" | "end"

---@type table<string, Beast.Toast.Progress.Entry>
local tokens = {}

---@type uv.uv_timer_t|nil
local timer = nil
local timer_running = false

-- =============================================================================
-- HELPERS
-- =============================================================================

---Time-derived spinner frame. No per-entry state.
---@return string
local function spinner()
	local frames = config.progress.spinner
	local interval = config.progress.spinner_interval
	local ms = math.floor(vim.uv.hrtime() / 1e6)
	local idx = math.floor(ms / interval) % #frames + 1
	return frames[idx]
end

---Build the segment list for an entry. The plain-text message is derived
---from the segments via table.concat so the two can never drift.
---Shapes:
---  with percentage: "<title>  ⠹  [████░░░░░░░░░░░░░░░░] 42%  <message>"
---  no percentage:   "<title>  ⠹  <message>"
---  done:            "<title>  ✔  <message>"
---@param entry Beast.Toast.Progress.Entry
---@return string text
---@return Beast.Toast.Fragment[] segments
local function format_line(entry)
	local title = entry.title or ""
	local msg = entry.message or ""
	local segs

	if entry.kind == "end" then
		segs = {
			{ text = title, hl = "BeastToastProgressTitle" },
			{ text = "  " },
			{ text = "✔", hl = "BeastToastProgressDone" },
			{ text = "  " },
			{ text = msg ~= "" and msg or "done", hl = "BeastToastProgressMessage" },
		}
	else
		local spin = spinner()
		if entry.percentage ~= nil then
			local width = config.progress.bar_width
			local pct = math.max(0, math.min(100, entry.percentage))
			local done = math.floor(pct / 100 * width + 0.5)
			segs = {
				{ text = title, hl = "BeastToastProgressTitle" },
				{ text = "  " },
				{ text = spin, hl = "BeastToastProgressSpinner" },
				{ text = "  " },
				{ text = "[", hl = "BeastToastProgressBracket" },
				{ text = string.rep("█", done), hl = "BeastToastProgressBarDone" },
				{ text = string.rep("░", width - done), hl = "BeastToastProgressBarTodo" },
				{ text = "] ", hl = "BeastToastProgressBracket" },
				{ text = ("%d%%"):format(pct), hl = "BeastToastProgressPercent" },
				{ text = "  " },
				{ text = msg, hl = "BeastToastProgressMessage" },
			}
		else
			segs = {
				{ text = title, hl = "BeastToastProgressTitle" },
				{ text = "  " },
				{ text = spin, hl = "BeastToastProgressSpinner" },
				{ text = "  " },
				{ text = msg, hl = "BeastToastProgressMessage" },
			}
		end
	end

	local parts = {}
	for i, s in ipairs(segs) do
		parts[i] = s.text
	end
	return table.concat(parts), segs
end

-- =============================================================================
-- EVENT HANDLING
-- =============================================================================

---Forward declaration: defined after `tick` below.
local ensure_timer

---Merge an LSP progress event into an entry. Creates the toast on first event.
---@param client_id integer
---@param params lsp.ProgressParams
local function on_event(client_id, params)
	if not params or not params.token or not params.value then
		return
	end

	local id = client_id .. "." .. tostring(params.token)
	local entry = tokens[id]
	local value = params.value

	if not entry then
		local client = vim.lsp.get_client_by_id(client_id)
		-- The autocmd can outlive the client briefly; bail rather than guess a name.
		if not client then
			return
		end
		entry = {
			client_id = client_id,
			client_name = client.name,
			title = value.title or "",
			message = value.message or "",
			percentage = value.percentage,
			kind = value.kind or "begin",
		}
		local text, segs = format_line(entry)
		local record = toast(text, "INFO", {
			title = entry.client_name,
			timeout = false,
			segments = segs,
		})
		-- toast() returns {} when filtered by level; bail without registering.
		if not record or not record.id then
			return
		end
		entry.record = record
		tokens[id] = entry
	else
		entry.title = value.title or entry.title
		entry.message = value.message or entry.message
		if value.percentage ~= nil then
			entry.percentage = value.percentage
		end
		entry.kind = value.kind or entry.kind
	end

	if entry.kind == "end" and entry.percentage ~= nil then
		entry.percentage = 100
	end

	-- Repaint immediately so the begin/end frame is visible even if the timer
	-- has not yet fired (or is about to stop).
	local text, segs = format_line(entry)
	entry.record.message = text
	entry.record.segments = segs
	toast.update(entry.record)

	if entry.kind == "end" then
		local stale_id = entry.record.id
		vim.defer_fn(function()
			-- Guard against same-token reuse: if a fresh `begin` arrived for this id
			-- within done_linger, kind will have flipped back — don't dismiss.
			local cur = tokens[id]
			if cur and cur.record.id == stale_id and cur.kind == "end" then
				toast.dismiss_id(stale_id)
				tokens[id] = nil
			end
		end, config.progress.done_linger)
		return
	end

	ensure_timer()
end

-- =============================================================================
-- TIMER LOOP
-- =============================================================================

---Throttled frame: re-renders every active (non-end) token.
local function tick()
	if vim.tbl_isempty(tokens) then
		if timer then
			timer:stop()
		end
		timer_running = false
		return
	end

	for id, entry in pairs(tokens) do
		if entry.kind ~= "end" then
			if not vim.lsp.get_client_by_id(entry.client_id) then
				toast.dismiss_id(entry.record.id)
				tokens[id] = nil
			else
				local text, segs = format_line(entry)
				entry.record.message = text
				entry.record.segments = segs
				toast.update(entry.record)
			end
		end
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
M._tokens = tokens

return M
