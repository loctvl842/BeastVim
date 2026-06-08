local uv = vim.uv or vim.loop

---@class Beast.Finder.Source.LiveGrep: Beast.Finder.ASource
local M = {}

M.async = true
M.live = true
M.cmd = nil
M.args = {}

-- Maximum results to collect before stopping the process
local RESULT_LIMIT = 10000

-- Whether the active command uses NUL byte as filename separator
local use_nul_sep = false

---@param text string search query
---@param cwd string
local function ensure_cmd(text, cwd)
	if vim.fn.executable("ug") == 1 then
		M.cmd = "ug"
		use_nul_sep = false
		M.args = {
			"-r",
			"--format=%f:%n:%k:%O%~",
			"--color=never",
			"--smart-case",
			"--hidden",
			"--exclude-dir=.git",
			"--tabs=1",
			"--",
			text,
			cwd,
		}
	elseif vim.fn.executable("rg") == 1 then
		M.cmd = "rg"
		use_nul_sep = true
		M.args = {
			"--color=never",
			"--no-heading",
			"--with-filename",
			"--line-number",
			"--column",
			"--smart-case",
			"--hidden",
			"--max-columns=500",
			"--max-columns-preview",
			"--glob=!.git",
			"-0",
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

--- Parse a grep output line
--- With NUL sep (rg -0): file\0line:col:text
--- Without (ug/rg default): file:line:col:text
local function parse_line(line)
	if use_nul_sep then
		local nul = line:find("\0")
		if not nul then
			return nil
		end
		local file = line:sub(1, nul - 1)
		local lnum, col, text = line:sub(nul + 1):match("^(%d+):(%d+):(.*)$")
		if not lnum then
			return nil
		end
		return file, tonumber(lnum), tonumber(col) - 1, text
	end
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
			vim.notify("beast.finder: ug (ugrep) or rg (ripgrep) is required for live_grep", vim.log.levels.WARN)
			cb(nil)
		end)
		return
	end

	local cwd = filter.cwd
	local idx = 0
	local completed = false
	local prev = "" -- partial line from previous chunk
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

		-- Flush remaining partial line
		if prev ~= "" then
			local line = vim.trim(prev)
			prev = ""
			if line ~= "" then
				local file, lnum, col, text = parse_line(line)
				if file and idx < RESULT_LIMIT then
					idx = idx + 1
					local abs = make_abs(cwd, file)
					local rel = make_rel(cwd, abs)
					cb({
						idx = idx,
						score = 0,
						text = rel .. ":" .. lnum .. ": " .. text,
						file = abs,
						pos = { lnum, col },
						cwd = cwd,
						grep_text = text,
					})
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

		-- Parse lines directly from each chunk, tracking partial trailing line
		local batch = {}
		local from = 1
		while from <= #data do
			local nl = data:find("\n", from, true)
			if not nl then
				-- No more newlines — save as partial line for next chunk
				if prev ~= "" then
					prev = prev .. data:sub(from)
				else
					prev = data:sub(from)
				end
				break
			end

			local line = data:sub(from, nl - 1)
			from = nl + 1
			if prev ~= "" then
				line = prev .. line
				prev = ""
			end

			-- Strip \r if present
			if line:byte(#line) == 13 then
				line = line:sub(1, -2)
			end

			if line ~= "" then
				local file, lnum, col, text = parse_line(line)
				if file then
					idx = idx + 1
					if idx > RESULT_LIMIT then
						completed = true
						M.cancel()
						for _, item in ipairs(batch) do
							cb(item)
						end
						vim.schedule(function()
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

		if #batch > 0 then
			for _, item in ipairs(batch) do
				cb(item)
			end
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
