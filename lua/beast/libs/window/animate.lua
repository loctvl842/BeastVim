---Split-window resize animator built on `animate.tween`.
---Single-flight: a new run() cancels the in-flight tween and starts fresh from
---current widths (smooth redirect, no jump-back).
local config = require("beast.libs.window.config")
local tween_core = require("beast.libs.animate")
local win = require("beast.libs.window.win")
local api = vim.api

local M = {}

---@type {running:boolean}|nil
local current

local function round(n)
	return math.floor(n + 0.5)
end

local function resolve_easing(e)
	if type(e) == "function" then
		return e
	end
	return tween_core.easings[e] or tween_core.easings.ease_in_out
end

---@param data Beast.Window.WinResizeData[]
---@param on_done? fun()
function M.run(data, on_done)
	if vim.tbl_isempty(data) then
		if on_done then
			on_done()
		end
		return
	end

	if current then
		current.running = false
	end

	local entries = {}
	for _, d in ipairs(data) do
		if win.is_valid(d.winid) then
			local e = { winid = d.winid }
			if d.width then
				e.w0 = api.nvim_win_get_width(d.winid)
				e.dw = d.width - e.w0
			end
			if d.height then
				e.h0 = api.nvim_win_get_height(d.winid)
				e.dh = d.height - e.h0
			end
			entries[#entries + 1] = e
		end
	end

	local handle = { running = true }
	current = handle
	local ease = resolve_easing(config.animation.easing)

	tween_core.tween(config.animation.duration or 150, function(t)
		if not handle.running then
			return false
		end
		local k = ease(t)
		for _, e in ipairs(entries) do
			if win.is_valid(e.winid) then
				if e.dw then
					win.set_width(e.winid, e.w0 + round(k * e.dw))
				end
				if e.dh then
					win.set_height(e.winid, e.h0 + round(k * e.dh))
				end
			end
		end
	end, function()
		for _, e in ipairs(entries) do
			if win.is_valid(e.winid) then
				if e.dw then
					win.set_width(e.winid, e.w0 + e.dw)
				end
				if e.dh then
					win.set_height(e.winid, e.h0 + e.dh)
				end
			end
		end
		handle.running = false
		if current == handle then
			current = nil
		end
		if on_done then
			on_done()
		end
	end)
end

function M.finish()
	if current then
		current.running = false
		current = nil
	end
end

return M
