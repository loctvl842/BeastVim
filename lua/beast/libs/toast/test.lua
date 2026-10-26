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

---Same warning every 400 ms: one toast whose "xN" count climbs and which stays
---until the repeats stop; then two other messages interleaved with a repeated one.
function M.repeats()
	for i = 1, 8 do
		vim.defer_fn(function()
			toast("Pattern not found: foo", "WARN", { title = "Search" })
		end, i * 400)
	end
	vim.defer_fn(function()
		toast("file saved", "INFO")
		toast("Format failed", "ERROR", { title = "Conform" })
		toast("file saved", "INFO")
	end, 4200)
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

---Smoke test for the LSP progress adapter - fakes sequences of LspProgress
---events without needing an actual LSP server. Stubs vim.lsp.get_client_by_id
---so the fake clients are recognised.
---  fake_pyright: bursts of begin("")/report/end cycles with the same message.
---                Expect ONE toast: "1 file to analyze", then "(n)" repainted
---                at most once per show_delay window, then a final ✔ frame.
---                A cycle during the linger continues the same toast and count.
---  fake_lua_ls:  one long titled token with a percentage bar (never counted).
function M.test_progress()
	require("beast.libs.toast.progress").setup()

	local names = { [9001] = "fake_pyright", [9002] = "fake_lua_ls" }
	local orig = vim.lsp.get_client_by_id
	vim.lsp.get_client_by_id = function(id)
		if names[id] then
			return { id = id, name = names[id] }
		end
		return orig(id)
	end

	local function fire(client_id, token, value)
		vim.api.nvim_exec_autocmds("LspProgress", {
			data = { client_id = client_id, params = { token = token, value = value } },
		})
	end

	local function at(ms, fn)
		vim.defer_fn(fn, ms)
	end

	local function py_cycle(start, token, hold)
		at(start, function()
			fire(9001, token, { kind = "begin", title = "" })
		end)
		at(start + 5, function()
			fire(9001, token, { kind = "report", message = "1 file to analyze" })
		end)
		at(start + hold, function()
			fire(9001, token, { kind = "end" })
		end)
	end

	-- 8 tiny cycles 250 ms apart: one toast whose count climbs.
	for i = 0, 7 do
		py_cycle(i * 250, "py-burst-" .. i, 40)
	end
	-- Starts inside done_linger: same toast, count continues.
	py_cycle(2600, "py-reuse", 40)

	-- lua_ls-like: titled token with percentage.
	at(0, function()
		fire(9002, "lua", { kind = "begin", title = "Diagnosing", message = "0/20", percentage = 0 })
	end)
	for i = 1, 9 do
		at(i * 300, function()
			fire(9002, "lua", { kind = "report", message = (i * 2) .. "/20", percentage = i * 10 })
		end)
	end
	at(3000, function()
		fire(9002, "lua", { kind = "end" })
	end)

	at(5000, function()
		vim.lsp.get_client_by_id = orig
	end)
end

M.burst()

return M
