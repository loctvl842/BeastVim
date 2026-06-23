--- Shared factory for LSP-backed finder sources.
---
--- Async source: fires the LSP request and streams each unique location to the
--- finder via `cb(item)`, then `cb(nil)` once every client has responded.
--- The early single-result jump is handled by the match pipeline (via the
--- `auto_select` flag), not here — the source is a pure data producer.

local M = {}

---@param cwd string
---@param path string
---@return string
local function make_rel(cwd, path)
	local prefix = cwd:sub(-1) == "/" and cwd or (cwd .. "/")
	if path:sub(1, #prefix) == prefix then
		return path:sub(#prefix + 1)
	end
	return path
end

--- Build a single source table for one of the supported LSP methods.
---@param method "textDocument/definition"|"textDocument/references"|"textDocument/declaration"|"textDocument/implementation"
---@return Beast.Finder.ASource
function M.create(method)
	local source = {
		live = false,
		async = true,
		auto_select = true,
	}

	---@param filter Beast.Finder.Filter
	---@param cb fun(item: Beast.Finder.Item|nil) nil signals completion
	function source.get(filter, cb)
		local win = filter.cur_win
		local buf = vim.api.nvim_win_get_buf(win)

		local clients = vim.lsp.get_clients({ bufnr = buf, method = method })
		if #clients == 0 then
			vim.notify("beast.finder.lsp: no client supports " .. method, vim.log.levels.WARN)
			cb(nil)
			return
		end

		-- Build params once. Encoding is best-effort: use the first capable
		-- client's encoding (mixed-encoding setups are rare; locations_to_items
		-- still applies the *responding* client's encoding per result below).
		local enc = clients[1].offset_encoding or "utf-16"
		local ok, params = pcall(vim.lsp.util.make_position_params, win, enc)
		if not ok then
			vim.notify("beast.finder: failed to build LSP params: " .. tostring(params), vim.log.levels.ERROR)
			cb(nil)
			return
		end
		if method == "textDocument/references" then
			---@cast params lsp.ReferenceParams
			params.context = { includeDeclaration = true }
		end

		local cwd = filter.cwd
		local seen = {} ---@type table<string, true>
		local idx = 0

		-- buf_request_all fires the handler exactly once, after every client has
		-- responded, computing the pending count lazily. This avoids the race
		-- where an upfront client count never decrements to zero (a client shut
		-- down between get_clients and the request) — which would leave the
		-- source never signalling completion and spin the collector loop forever.
		---@param results table<integer, {err: lsp.ResponseError?, result: any}>
		vim.lsp.buf_request_all(buf, method, params, function(results)
			for client_id, res in pairs(results) do
				local result = res.result
				if not res.err and result then
					if result.uri or result.targetUri then
						result = { result }
					end
					if #result > 0 then
						local client = vim.lsp.get_client_by_id(client_id)
						local client_enc = client and client.offset_encoding or "utf-16"
						-- One libuv read per unique file; only needed rows are scanned.
						local qf_items = vim.lsp.util.locations_to_items(result, client_enc)
						for _, it in ipairs(qf_items) do
							local key = it.filename .. ":" .. it.lnum .. ":" .. it.col
							if not seen[key] then
								seen[key] = true
								idx = idx + 1
								local rel = make_rel(cwd, it.filename)
								cb({
									idx = idx,
									score = 0,
									text = rel .. ":" .. it.lnum .. ": " .. it.text,
									file = it.filename,
									-- locations_to_items returns 1-indexed col; finder.pos uses 0-indexed
									pos = { it.lnum, math.max(0, it.col - 1) },
									end_pos = { it.end_lnum or it.lnum, math.max(0, (it.end_col or it.col) - 1) },
									cwd = cwd,
									grep_text = it.text,
								})
							end
						end
					end
				end
			end

			if idx == 0 then
				vim.notify("beast.finder.lsp: no " .. method:gsub("^textDocument/", "") .. " found", vim.log.levels.INFO)
			end
			cb(nil)
		end)
	end

	return source
end

return M
