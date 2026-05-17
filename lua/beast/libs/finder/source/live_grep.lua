local uv = vim.uv or vim.loop

---@class Beast.Finder.Source.LiveGrep: Beast.Finder.ASource
local M = {}

M.async = true
M.live = true
M.cmd = nil
M.args = {}

-- Maximum results to collect before stopping the process
local RESULT_LIMIT = 10000

---@param text string search query
---@param cwd string
local function ensure_cmd(text, cwd)
	if vim.fn.executable("rg") == 1 then
		M.cmd = "rg"
		M.args = {
			"--vimgrep",
			"--color=never",
			"--no-heading",
			"--smart-case",
			"--hidden",
			"--glob",
			"!.git",
			"--",
			text,
			cwd,
		}
	else
		M.cmd = nil
		M.args = {}
	end
end

--- Build a relative path from an absolute one without vim.fn (safe in libuv callbacks)
---@param cwd string
---@param path string
---@return string
local function make_rel(cwd, path)
	-- Ensure cwd ends with / for reliable prefix stripping
	local cwd_prefix = cwd:sub(-1) == "/" and cwd or (cwd .. "/")
	if path:sub(1, #cwd_prefix) == cwd_prefix then
		return path:sub(#cwd_prefix + 1)
	end
	return path
end

--- Normalize path to absolute without vim.fn
---@param cwd string
---@param path string
---@return string
local function make_abs(cwd, path)
	-- Ensure cwd ends with / for reliable prefix stripping
	local cwd_prefix = cwd:sub(-1) == "/" and cwd or (cwd .. "/")
	if path:sub(1, 1) == "/" then
		return path
	end
	return cwd_prefix .. path
end

--- Parse a vimgrep line: file:line:col:text
local function parse_line(line)
	local file, lnum, col, text = line:match("^(.+):(%d+):(%d+):(.*)$")
	if not file then
		return nil
	end
	return file, tonumber(lnum), tonumber(col) - 1, text
end

---@type uv.uv_process_t|nil
local current_handle = nil
---@type uv.uv_pipe_t|nil
local current_stdout = nil

---@param filter Beast.Finder.Filter
---@param cb fun(item: Beast.Finder.Item|nil) nil signals completion
function M.get(filter, cb)
	M.cancel()
	if filter.pattern == "" or filter.pattern == nil then
		vim.schedule(function()
			cb(nil)
		end)
		return
	end

	ensure_cmd(filter.pattern, filter.cwd)
	if not M.cmd then
		vim.schedule(function()
			vim.notify("beast.finder: rg (ripgrep) is required for live_grep", vim.log.levels.WARN)
			cb(nil)
		end)
		return
	end

	local cwd = filter.cwd
	local idx = 0
	local completed = false
	local chunks = {} -- collect chunks instead of concatenating strings
	local stdout = assert(uv.new_pipe(false), "failed to create stdout pipe")
	current_stdout = stdout

	---@type uv.spawn.options
	local spawn_opts = {
		args = M.args,
		stdio = { nil, stdout, nil },
		cwd = nil,
		env = nil,
		uid = nil,
		gid = nil,
		verbatim = false,
		detached = false,
		hide = true,
	}

	local handle
	handle = uv.spawn(M.cmd, spawn_opts, function()
		if not stdout:is_closing() then
			stdout:close()
		end
		if handle and not handle:is_closing() then
			handle:close()
		end
		current_handle = nil
		current_stdout = nil

		-- If limit was already reached, don't signal completion again
		if completed then
			return
		end
		completed = true

		-- Flush remaining data
		local remaining = table.concat(chunks)
		chunks = {}
		if remaining ~= "" then
			local line = vim.trim(remaining)
			if line ~= "" then
				local file, lnum, col, text = parse_line(line)
				if file and idx < RESULT_LIMIT then
					idx = idx + 1
					local abs = make_abs(cwd, file)
					local rel = make_rel(cwd, abs)
					local item = {
						idx = idx,
						score = 0,
						text = rel .. ":" .. lnum .. ": " .. text,
						file = abs,
						pos = { lnum, col },
						cwd = cwd,
						grep_text = text,
					}
					vim.schedule(function()
						cb(item)
					end)
				end
			end
		end
		vim.schedule(function()
			cb(nil)
		end)
	end)

	current_handle = handle

	stdout:read_start(function(err, data)
		if err or not data then
			return
		end

		-- Collect chunk and process lines
		chunks[#chunks + 1] = data
		local buf = table.concat(chunks)
		chunks = {}

		local batch = {}
		local pos = 1
		while true do
			local nl = buf:find("\n", pos, true)
			if not nl then
				break
			end
			local line = buf:sub(pos, nl - 1)
			pos = nl + 1

			line = vim.trim(line)
			if line ~= "" then
				local file, lnum, col, text = parse_line(line)
				if file then
					idx = idx + 1
					if idx > RESULT_LIMIT then
						-- Hit limit — stop reading and kill the process
						completed = true
						M.cancel()
						vim.schedule(function()
							for _, item in ipairs(batch) do
								cb(item)
							end
							cb(nil)
						end)
						return
					end
					local abs = make_abs(cwd, file)
					local rel = make_rel(cwd, abs)
					batch[#batch + 1] = {
						idx = idx,
						score = 0,
						text = rel .. ":" .. lnum .. ": " .. text,
						file = abs,
						pos = { lnum, col },
						cwd = cwd,
						grep_text = text,
					}
				end
			end
		end
		-- Keep the trailing partial line
		if pos <= #buf then
			chunks[1] = buf:sub(pos)
		end

		if #batch > 0 then
			vim.schedule(function()
				for _, item in ipairs(batch) do
					cb(item)
				end
			end)
		end
	end)
end

--- Cancel any running grep process
function M.cancel()
	if current_stdout then
		pcall(function()
			current_stdout:read_stop()
			current_stdout:close()
		end)
		current_stdout = nil
	end
	if current_handle then
		pcall(function()
			current_handle:kill("SIGTERM")
			current_handle:close()
		end)
		current_handle = nil
	end
end

return M
