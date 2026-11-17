-- `cond` on a keymap spec: decides whether the keymap is registered at all.
--
--   boolean                      fixed answer
--   function() return ok end     quick check, answers at once
--   function(done) ... done(ok)  slow check (e.g. an external command): the keymap is registered right
--                                away as a placeholder that only toasts, then swapped for the real keymap
--                                on yes or removed on no / error / timeout
--
-- core.lua requires this module at load, so core is only required lazily inside functions.

local M = {}

M.timeout_ms = 10000

---@class Beast.Key.Cond.Entry
---@field key string pending-table key (keymap id + buffer)
---@field spec Beast.KeymapSpec the real keymap for one mode
---@field buffer? integer resolved buffer of a buffer-local keymap

---@class Beast.Key.Cond.Token
---@field spec Beast.KeymapSpec
---@field site? Beast.Keymap.CallSite where the keymap was registered
---@field entries Beast.Key.Cond.Entry[]
---@field timer? uv.uv_timer_t

---A pending check is current only while its token is the one stored for its keymap; a later registration or
---a delete drops the entry, which turns the late answer into a no-op.
---@type table<string, Beast.Key.Cond.Token>
local pending = {}

---Name used in messages about a keymap.
---@param spec Beast.KeymapSpec
---@return string
local function name(spec)
	return (spec.desc and spec.desc ~= "") and spec.desc or spec[1]
end

---@param spec Beast.KeymapSpec
---@param reason string
local function warn(spec, reason)
	require("beast.libs.toast")(("%s disabled: %s"):format(name(spec), reason), "WARN", { title = "key" })
end

---@param id string
---@param buffer? integer|boolean
---@return string
local function pending_key(id, buffer)
	if buffer == true or buffer == 0 then
		buffer = vim.api.nvim_get_current_buf()
	end
	return id .. "\0" .. (buffer or "g")
end

---Forget the pending check of a keymap (it was deleted or registered again).
---@param id string
---@param buffer? integer|boolean
function M.cancel(id, buffer)
	pending[pending_key(id, buffer)] = nil
end

---The keymap pressed while its check runs: says so and does nothing else.
---@param spec Beast.KeymapSpec
---@return Beast.KeymapSpec
local function placeholder(spec)
	local p = vim.deepcopy(spec)
	p[2] = function()
		require("beast.libs.toast")(("%s: still checking"):format(name(spec)), "INFO", { title = "key" })
	end
	p.expr, p.once, p.replace_keycodes = nil, nil, nil
	return p
end

---Register the placeholders of a slow check, one per mode.
---@param spec Beast.KeymapSpec
---@param modes string[]
---@param buffer? integer|boolean
---@param site? Beast.Keymap.CallSite
---@return Beast.Key.Cond.Token
local function hold(spec, modes, buffer, site)
	local core = require("beast.libs.key.core")
	if buffer == true or buffer == 0 then
		buffer = vim.api.nvim_get_current_buf()
	end
	local token = { spec = spec, site = site, entries = {} } ---@type Beast.Key.Cond.Token
	for _, m in ipairs(modes) do
		local real = vim.tbl_extend("force", spec, { mode = m })
		local key = pending_key(core.id(real[1], m), buffer)
		-- A label-only entry has no action to block: it is listed once the check says yes
		if real[2] ~= nil then
			core.set(placeholder(real), buffer, site)
		end
		pending[key] = token
		table.insert(token.entries, { key = key, spec = real, buffer = buffer or nil })
	end
	return token
end

---The check ended: swap the placeholders for the real keymaps (ok) or remove them (not ok).
---@param token Beast.Key.Cond.Token
---@param ok boolean
---@param reason? string Why a failed check ended, shown once; a plain "no" has none
local function settle(token, ok, reason)
	local timer = token.timer
	if timer and not timer:is_closing() then
		timer:stop()
		timer:close()
	end
	local core = require("beast.libs.key.core")
	local live = false
	for _, e in ipairs(token.entries) do
		if pending[e.key] == token then
			pending[e.key] = nil
			if not e.buffer or vim.api.nvim_buf_is_valid(e.buffer) then
				live = true
				if ok then
					if e.spec[2] ~= nil then
						core.set(e.spec, e.buffer, token.site)
					else
						core.label(e.spec, e.buffer)
					end
				elseif e.spec[2] ~= nil then
					core.del({ e.spec[1], mode = e.spec.mode }, e.buffer)
				end
			end
		end
	end
	if live and reason then
		warn(token.spec, reason)
	end
end

---Check the condition of a keymap about to be registered.
---Returns "yes" or "no" for an answer at once; "pending" when a slow check is running, in which case the
---placeholders are already registered and the rest happens when the check ends.
---@param spec Beast.KeymapSpec
---@param modes string[]
---@param buffer? integer|boolean
---@param site? Beast.Keymap.CallSite
---@return "yes"|"no"|"pending"
function M.resolve(spec, modes, buffer, site)
	local cond = spec.cond
	if type(cond) ~= "function" then
		return cond == false and "no" or "yes"
	end

	local token ---@type Beast.Key.Cond.Token
	local finished, sync, answer = false, true, false
	local function done(ok)
		if finished then
			return
		end
		finished = true
		if sync then
			answer = ok == true
			return
		end
		-- Usually called from a process callback, where the editor API is not available
		vim.schedule(function()
			settle(token, ok == true)
		end)
	end

	local ok, ret = pcall(cond, done)
	sync = false
	if not ok then
		finished = true
		warn(spec, "cond raised an error: " .. tostring(ret))
		return "no"
	end
	if ret ~= nil then
		finished = true
		return ret == true and "yes" or "no"
	end
	if finished then
		return answer and "yes" or "no"
	end

	token = hold(spec, modes, buffer, site)
	token.timer = vim.defer_fn(function()
		if finished then
			return
		end
		finished = true
		settle(token, false, ("check timed out (%ds)"):format(M.timeout_ms / 1000))
	end, M.timeout_ms)
	return "pending"
end

return M
