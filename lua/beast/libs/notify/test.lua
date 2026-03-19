local notify = require("beast.libs.notify")

local M = {}

---@param n integer
---@return string
local function rand_text(n)
	local parts = {}
	for i = 1, n do
		parts[i] = ("line %02d - lorem ipsum dolor sit amet"):format(i)
	end
	return table.concat(parts, "\n")
end

---@param i integer
---@return string
local function pick_level(i)
	local levels = { "INFO", "WARN", "ERROR", "DEBUG", "TRACE" }
	return levels[((i - 1) % #levels) + 1]
end

---@param i integer
---@return string|string[]
local function make_message(i)
	local mode = i % 4

	if mode == 0 then
		return ("notif #%03d"):format(i)
	elseif mode == 1 then
		return ("notif #%03d\nsecond line"):format(i)
	elseif mode == 2 then
		return rand_text(3)
	end

	return rand_text(6)
end

---@param total integer
---@param interval integer
---@param timeout integer
local function run_series(total, interval, timeout)
	local sent = 0
	local timer = vim.loop.new_timer()

	timer:start(
		0,
		interval,
		vim.schedule_wrap(function()
			sent = sent + 1

			if sent > total then
				timer:stop()
				timer:close()
				print(("stress done: sent %d notifications"):format(total))
				return
			end

			notify(make_message(sent), pick_level(sent), {
				title = ("Stress %03d"):format(sent),
				timeout = timeout,
			})
		end)
	)
end

function M.burst()
	for i = 1, 50 do
		notify(make_message(i), pick_level(i), {
			title = ("Burst %03d"):format(i),
			timeout = 1500,
		})
	end
end

function M.series_fast()
	run_series(100, 20, 1200)
end

function M.series_medium()
	run_series(100, 80, 1800)
end

function M.series_slow()
	run_series(50, 150, 2200)
end

function M.mixed()
	for i = 1, 20 do
		vim.defer_fn(function()
			notify(make_message(i), pick_level(i), {
				title = ("Mixed %03d"):format(i),
				timeout = 800 + (i % 5) * 400,
			})
		end, (i - 1) * 35)
	end
end

function M.long_run()
	run_series(300, 30, 1000)
end

function M.dismiss_midway()
	run_series(40, 40, 3000)

	vim.defer_fn(function()
		local ok, stack = pcall(require, "beast.libs.notify.stack")
		local ok2, state_mod = pcall(require, "beast.libs.notify.state")
		if ok and ok2 then
			print("manual dismiss test: call your plugin dismiss hook from here if exported")
		end
	end, 700)
end

return M
