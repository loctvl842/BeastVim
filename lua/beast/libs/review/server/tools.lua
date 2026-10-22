-- The editor tools Claude Code may call. Only what the review flow needs:
-- openDiff plus the small set the CLI expects an IDE to answer.
--
-- Tools without a `description` are callable but not advertised in tools/list.

local jsonrpc = require("beast.libs.review.server.jsonrpc")

local M = {}

---@param s string
---@return table
local function text(s)
	return { content = { { type = "text", text = s } } }
end

---@param code integer
---@param message string
local function fail(code, message)
	return nil, jsonrpc.error(code, message)
end

---@type table<table, true>  every review currently waiting on the user
local open_diffs = {}

---@param pred? fun(entry: table): boolean
---@return integer cancelled
local function cancel_diffs(pred)
	local n = 0
	for entry in pairs(open_diffs) do
		if not pred or pred(entry) then
			n = n + 1
			entry.cancel()
		end
	end
	return n
end

---@type table<string, { description?: string, inputSchema?: table, handler: fun(args: table, ctx: Beast.Review.RpcCtx): table?, table? }>
M.tools = {
	openDiff = {
		description = "Open a diff of a proposed change and wait for the user to accept or reject it",
		inputSchema = {
			type = "object",
			properties = {
				old_file_path = { type = "string", description = "Path to the original file" },
				new_file_path = { type = "string", description = "Path to the file being changed" },
				new_file_contents = { type = "string", description = "Proposed contents of the file" },
				tab_name = { type = "string", description = "Name of the diff tab" },
			},
			required = { "old_file_path", "new_file_path", "new_file_contents", "tab_name" },
			additionalProperties = false,
			["$schema"] = "http://json-schema.org/draft-07/schema#",
		},
		handler = function(args, ctx)
			if type(args.new_file_path) ~= "string" or type(args.new_file_contents) ~= "string" then
				return fail(jsonrpc.ERR.PARAMS, "new_file_path and new_file_contents are required strings")
			end

			local path = vim.fs.normalize(args.new_file_path)
			if path == "" or vim.fn.isdirectory(path) == 1 then
				return fail(jsonrpc.ERR.PARAMS, "new_file_path must name a file")
			end

			-- Registered before proposing: the review can complete synchronously.
			local entry = { tab_name = args.tab_name }
			open_diffs[entry] = true
			entry.cancel = require("beast.libs.review").propose(path, args.new_file_contents, function(outcome, stats)
				open_diffs[entry] = nil
				if outcome == "saved" then
					ctx.reply(text("FILE_SAVED"))
				elseif outcome == "error" then
					ctx.reply(nil, jsonrpc.error(jsonrpc.ERR.INTERNAL, "Could not save file", stats.message))
				else
					ctx.reply(text("DIFF_REJECTED")) -- rejected, or cancelled before the user decided
				end
			end)
			ctx.on_cancel(entry.cancel)
			return jsonrpc.DEFERRED
		end,
	},

	closeAllDiffTabs = {
		description = "Close all diff tabs in the editor",
		inputSchema = { type = "object", additionalProperties = false },
		handler = function()
			return text(("CLOSED_%d_DIFF_TABS"):format(cancel_diffs()))
		end,
	},

	close_tab = {
		handler = function(args)
			cancel_diffs(function(entry)
				return entry.tab_name == args.tab_name
			end)
			return text("TAB_CLOSED")
		end,
	},

	getWorkspaceFolders = {
		description = "Get all workspace folders currently open in the IDE",
		inputSchema = { type = "object", additionalProperties = false },
		handler = function()
			local cwd = vim.fn.getcwd()
			return text(vim.json.encode({
				success = true,
				folders = { { name = vim.fn.fnamemodify(cwd, ":t"), uri = "file://" .. cwd, path = cwd } },
				rootPath = cwd,
			}))
		end,
	},

	getOpenEditors = {
		description = "Get list of currently open files",
		inputSchema = { type = "object", additionalProperties = false },
		handler = function()
			local current, tabs = vim.api.nvim_get_current_buf(), {}
			for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				local name = vim.api.nvim_buf_get_name(buf)
				if vim.bo[buf].buflisted and vim.api.nvim_buf_is_loaded(buf) and name ~= "" then
					tabs[#tabs + 1] = {
						uri = "file://" .. name,
						isActive = buf == current,
						label = vim.fn.fnamemodify(name, ":t"),
						languageId = vim.bo[buf].filetype,
						isDirty = vim.bo[buf].modified,
					}
				end
			end
			return text(vim.json.encode({ tabs = tabs }))
		end,
	},

	openFile = {
		description = "Open a file in the editor",
		inputSchema = {
			type = "object",
			properties = { filePath = { type = "string", description = "Path to the file to open" } },
			required = { "filePath" },
			additionalProperties = false,
		},
		handler = function(args)
			if type(args.filePath) ~= "string" then
				return fail(jsonrpc.ERR.PARAMS, "filePath is required")
			end
			local path = vim.fn.fnamemodify(args.filePath, ":p")
			local win = require("beast.libs.view").win.find_normal()
			if win then
				vim.api.nvim_set_current_win(win)
			end
			vim.cmd.edit(vim.fn.fnameescape(path))
			return text("Opened file: " .. path)
		end,
	},
}

--- Tools advertised through tools/list.
---@return table[]
function M.list()
	local out = {}
	for name, tool in pairs(M.tools) do
		if tool.description then
			out[#out + 1] = { name = name, description = tool.description, inputSchema = tool.inputSchema }
		end
	end
	table.sort(out, function(a, b)
		return a.name < b.name
	end)
	return out
end

return M
