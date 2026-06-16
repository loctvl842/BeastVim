local Query = require("beast.libs.finder.query")

local M = {}

---@type Beast.Lib.Meta
M.meta = { name = "finder", description = "Fuzzy finder picker (files, grep, LSP, commands)" }

local query ---@type Beast.Finder.Query
local initialized = false

---@param opts? Beast.Finder.Config
function M.setup(opts)
	require("beast.libs.finder.config").setup(opts)
	require("beast").apply_highlights("beast.libs.finder.highlights")
	initialized = true
end

-- LSP source → method mapping. These sources are special: we run the LSP
-- request up-front (before opening the picker) so we can short-circuit to a
-- direct jump when there's exactly one unique location.
local LSP_METHOD = {
	lsp_definitions = "textDocument/definition",
	lsp_references = "textDocument/references",
	lsp_declarations = "textDocument/declaration",
	lsp_implementations = "textDocument/implementation",
}

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

--- Jump the original window to a finder item's file:line:col.
---@param item Beast.Finder.Item
local function jump_to(item)
	-- stylua: ignore
	if not item or not item.file then return end
	vim.cmd("edit " .. vim.fn.fnameescape(item.file))
	if item.pos then
		pcall(vim.api.nvim_win_set_cursor, 0, { math.max(1, item.pos[1]), item.pos[2] or 0 })
	end
end

--- Run a single LSP location-returning method, stream per-client responses,
--- then either jump (1 unique result) or open the finder with the pre-fetched
--- items.
---@param source_name string  one of `lsp_definitions|lsp_references|lsp_declarations`
---@param opts Beast.Finder.QueryOpts
local function open_lsp(source_name, opts)
	local method = LSP_METHOD[source_name]
	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_win_get_buf(win)
	local symbol = vim.fn.expand("<cword>")

	local clients = vim.lsp.get_clients({ bufnr = buf, method = method })
	if #clients == 0 then
		vim.notify("beast.finder.lsp: no client supports " .. method, vim.log.levels.WARN)
		return
	end

	-- Build params once. Encoding is best-effort: use the first capable
	-- client's encoding (mixed-encoding setups are rare; locations_to_items
	-- still applies the *responding* client's encoding per result below).
	local enc = clients[1].offset_encoding or "utf-16"
	local ok, params = pcall(vim.lsp.util.make_position_params, win, enc)
	if not ok then
		vim.notify("beast.finder: failed to build LSP params: " .. tostring(params), vim.log.levels.ERROR)
		return
	end
	if method == "textDocument/references" then
		params.context = { includeDeclaration = true }
	end

	local cwd = opts.cwd or Util.root({ buf = buf })
	local seen = {} ---@type table<string, true>
	local items = {} ---@type Beast.Finder.Item[]
	local pending = #clients

	---@param err lsp.ResponseError|nil
	---@param result lsp.Location|lsp.Location[]|lsp.LocationLink[]|nil
	---@param ctx lsp.HandlerContext
	local function handle(err, result, ctx)
		if not err and result then
			if result.uri or result.targetUri then
				result = { result }
			end
			if #result > 0 then
				local client = vim.lsp.get_client_by_id(ctx.client_id)
				local client_enc = client and client.offset_encoding or "utf-16"
				-- One libuv read per unique file; only needed rows are scanned.
				local qf_items = vim.lsp.util.locations_to_items(result, client_enc)
				for _, it in ipairs(qf_items) do
					local key = it.filename .. ":" .. it.lnum .. ":" .. it.col
					if not seen[key] then
						seen[key] = true
						local rel = make_rel(cwd, it.filename)
						items[#items + 1] = {
							idx = #items + 1,
							score = 0,
							text = rel .. ":" .. it.lnum .. ": " .. it.text,
							file = it.filename,
							-- locations_to_items returns 1-indexed col; finder.pos uses 0-indexed
							pos = { it.lnum, math.max(0, it.col - 1) },
							end_pos = { it.end_lnum or it.lnum, math.max(0, (it.end_col or it.col) - 1) },
							cwd = cwd,
							grep_text = it.text,
						}
					end
				end
			end
		end

		pending = pending - 1
		-- stylua: ignore
		if pending > 0 then return end

		-- All clients responded
		if #items == 0 then
			vim.notify("beast.finder.lsp: no " .. source_name:gsub("^lsp_", "") .. " found", vim.log.levels.INFO)
			return
		end
		if #items == 1 then
			jump_to(items[1])
			return
		end

		-- Open the picker with the pre-fetched results
		opts.lsp = { results = items, symbol = symbol ~= "" and symbol or nil }
		opts.cwd = cwd
		if query then
			query:close()
		end
		query = Query(source_name, opts)
	end

	vim.lsp.buf_request(buf, method, params, handle)
end

---@param source Beast.Finder.Source
---@param opts? Beast.Finder.QueryOpts
function M.open(source, opts)
	opts = opts or {}

	-- LSP keymaps can fire before the packer.lazy `keys` trigger initializes
	-- the finder. Run setup with defaults so config + highlights are ready.
	if not initialized then
		M.setup()
	end

	if LSP_METHOD[source] then
		return open_lsp(source, opts)
	end

	if query then
		query:close()
	end
	---@type Beast.Finder.Query
	query = Query(source, opts)
  M.query = query
end

return M
