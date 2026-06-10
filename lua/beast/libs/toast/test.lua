local toast = require("beast.libs.toast")

-- Wire up a default title so every test toast shows "BeastVim" at the right edge.
toast.setup()

local M = {}

---@param i integer
---@return string
local function pick_level(i)
	local levels = { "INFO", "WARN", "ERROR", "DEBUG", "TRACE" }
	return levels[((i - 1) % #levels) + 1]
end

---@param i integer
---@return string
local function make_message(i)
	local mode = i % 3
	if mode == 0 then
		return ("toast #%03d"):format(i)
	elseif mode == 1 then
		return ("toast #%03d - file saved"):format(i)
	end
	return ("toast #%03d - lorem ipsum dolor sit amet consectetur"):format(i)
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
				print(("toast stress done: sent %d toasts"):format(total))
				return
			end

			toast(make_message(sent), pick_level(sent), { timeout = timeout })
		end)
	)
end

function M.burst()
	for i = 1, 20 do
		toast(make_message(i), pick_level(i), { title = "BeastVim", timeout = 10500 })
	end
end

function M.loader()
	local plugins = {
		"which-key.nvim",
		"nvim-navic",
		"colorscheme",
		"nvim-web-devicons",
		"heirline.nvim",
	}
	for i, name in ipairs(plugins) do
		vim.defer_fn(function()
			toast("Loading " .. name, "INFO", { timeout = 3000 })
		end, (i - 1) * 120)
	end
end

function M.series_fast()
	run_series(50, 40, 1200)
end

function M.series_medium()
	run_series(50, 120, 1800)
end

function M.series_slow()
	run_series(30, 250, 2500)
end

function M.mixed()
	for i = 1, 15 do
		vim.defer_fn(function()
			toast(make_message(i), pick_level(i), { timeout = 800 + (i % 5) * 400 })
		end, (i - 1) * 50)
	end
end

function M.dismiss_midway()
	run_series(30, 80, 4000)

	vim.defer_fn(function()
		toast.dismiss()
		print("toast dismiss triggered")
	end, 900)
end

---Smoke test for the update-in-place + dismiss-by-id API.
---Pushes a sticky toast, mutates its message twice, then dismisses it.
function M.test_update()
	local record = toast("starting work...", "INFO", {
		title = "test_update",
		timeout = false,
	})
	if not record or not record.id then
		print("test_update: toast did not return a record (filtered by level?)")
		return
	end

	vim.defer_fn(function()
		record.message = "working on a longer message to force a resize..."
		toast.update(record)
	end, 400)

	vim.defer_fn(function()
		record.message = "done!"
		toast.update(record)
	end, 1000)

	vim.defer_fn(function()
		toast.dismiss_id(record.id)
		print("test_update: dismissed")
	end, 1800)
end

M.burst()

return M
