local config = require("beast.libs.explorer.config")
local prompt = require("beast.libs.explorer.prompt")
local state = require("beast.libs.explorer.state")
local ui = require("beast.libs.explorer.ui")

local uv = vim.uv or vim.loop

local M = setmetatable({}, {
	__call = function(t, ...)
		return t.run(...)
	end,
})

-- =============================================================================
-- Planning helpers
-- =============================================================================

---@alias PasteMode "copy"|"cut"

---@class Beast.Explorer.PastePlan
---@field src_path string
---@field dest_path string
---@field dest_dir string
---@field name string
---@field mode PasteMode

---@param src_path string
---@param dest_dir string
---@param mode PasteMode
---@param override_name string?
---@return Beast.Explorer.PastePlan
local function make_plan(src_path, dest_dir, mode, override_name)
	local name = override_name or vim.fn.fnamemodify(src_path, ":t")
	return {
		src_path = src_path,
		dest_path = dest_dir .. "/" .. name,
		dest_dir = dest_dir,
		name = name,
		mode = mode,
	}
end

---@param path string
---@return boolean
local function path_exists(path)
	return uv.fs_stat(path) ~= nil
end

-- =============================================================================
-- Session
-- =============================================================================

---@class Beast.Explorer.PasteSession
---@field paths string[]
---@field mode PasteMode
---@field dest_dir_node Beast.Explorer.Node
---@field errors string[]
local PasteSession = setmetatable({}, {
	__call = function(t, ...)
		return t:new(...)
	end,
})
PasteSession.__index = PasteSession

---@param opts { paths: string[], mode: PasteMode, dest_dir_node: Beast.Explorer.Node }
---@return Beast.Explorer.PasteSession
function PasteSession:new(opts)
	return setmetatable({
		paths = vim.deepcopy(opts.paths),
		mode = opts.mode,
		dest_dir_node = opts.dest_dir_node,
		errors = {},
	}, self)
end

function PasteSession:start()
	self:step()
end

function PasteSession:finish()
	state.clipboard = nil

	for _, err in ipairs(self.errors) do
		vim.notify(err, vim.log.levels.WARN)
	end
end

function PasteSession:_current_src_path()
	return self.paths[1]
end

---@param self Beast.Explorer.PasteSession
function PasteSession:_advance()
	table.remove(self.paths, 1)
	self:step()
end

---@param self Beast.Explorer.PasteSession
---@param err string?
function PasteSession:_add_error(err)
	if err and err ~= "" then
		table.insert(self.errors, err)
	end
end

function PasteSession:_remove_from_clipboard()
	-- stylua: ignore
	if not state.clipboard then return end
	table.remove(state.clipboard.paths, 1)
	ui.render()
end

function PasteSession:_rename(src_path, new_name)
	local plan = make_plan(src_path, self.dest_dir_node.path, self.mode, new_name)
	if path_exists(plan.dest_path) then
		vim.notify("Already exists: " .. new_name, vim.log.levels.WARN)
		return false
	end

	self:apply_plan(plan)
	return true
end

function PasteSession:step()
	local src_path = self:_current_src_path()
	if not src_path then
		self:finish()
		return
	end

	local plan = make_plan(src_path, self.dest_dir_node.path, self.mode)
	if path_exists(plan.dest_path) then
		self:show_conflict_prompt(plan)
		return
	end

	self:apply_plan(plan)
end

function PasteSession:show_conflict_prompt(plan)
	local src_path = plan.src_path
	local name = plan.name
	local dest_dir_node = self.dest_dir_node

	---@param new_name string
	local function on_confirm(new_name)
		local new_plan = make_plan(src_path, self.dest_dir_node.path, self.mode, new_name)
		if path_exists(new_plan.dest_path) then
			vim.notify("Already exists: " .. new_name, vim.log.levels.WARN)
			return false
		end

		-- callback to continue to the next path
		return function()
			self:apply_plan(new_plan)
		end
	end

	local function on_cancel()
		self:_remove_from_clipboard()
		self:_advance()
	end

	prompt.inline(dest_dir_node, dest_dir_node, on_confirm, on_cancel, name)
end

---@param src_path string
---@param dest_path string
---@return boolean ok
---@return string? err
local function copy_path(src_path, dest_path)
	vim.fn.system({ "cp", "-r", src_path, dest_path })
	if vim.v.shell_error ~= 0 then
		return false, "Copy failed: " .. vim.fn.fnamemodify(src_path, ":t")
	end
	return true, nil
end

---@param src_path string
---@param dest_path string
---@return boolean ok
---@return string? err
local function move_path(src_path, dest_path)
	local ok, err = uv.fs_rename(src_path, dest_path)
	if ok then
		return true, nil
	end

	-- Cross-device fallback: copy then delete
	local copied, copy_err = copy_path(src_path, dest_path)
	if not copied then
		return false, "Move failed: " .. vim.fn.fnamemodify(src_path, ":t") .. " (" .. (err or copy_err or "") .. ")"
	end

	vim.fn.delete(src_path, "rf")
	if vim.v.shell_error ~= 0 then
		return false, "Move cleanup failed: " .. vim.fn.fnamemodify(src_path, ":t")
	end

	return true, nil
end

---@param plan Beast.Explorer.PastePlan
---@return boolean ok
---@return string? err
local function execute_plan(plan)
	if plan.mode == "cut" then
		return move_path(plan.src_path, plan.dest_path)
	end
	return copy_path(plan.src_path, plan.dest_path)
end

---@param plan Beast.Explorer.PastePlan
function PasteSession:apply_plan(plan)
	local ok, err = execute_plan(plan)
	if not ok then
		self:_add_error(err)
		self:_advance()
		return
	end

	self:_remove_from_clipboard()

	-- Render after successful copy/move
	if plan.mode == "cut" then
		state.tree:refresh(vim.fs.dirname(plan.src_path))
	end

	state.tree:refresh(self.dest_dir_node.path)

	ui.render(function()
		ui.focus_path(plan.dest_path)
		self:_advance()
	end)
end

-- --------------------------------------------------------------------------
-- Entrypoint helpers
-- --------------------------------------------------------------------------

---@return Beast.Explorer.Node?
local function resolve_destination_dir_node()
	local node = state.current_node({ show_hidden = config.show_hidden })
  -- stylua: ignore
	if not node then return nil end

  -- stylua: ignore
	if node.dir then return node end

	return state.tree.nodes[node.parent or vim.fs.dirname(node.path)]
end

---@param dest_dir_node Beast.Explorer.Node
---@param cb fun()
local function ensure_destination_open(dest_dir_node, cb)
	if dest_dir_node.dir and dest_dir_node.open then
		state.tree:open(dest_dir_node.path)
		ui.render(cb)
		return
	end
	cb()
end

function M.run()
	if not state.clipboard or not state.clipboard.paths or #state.clipboard.paths == 0 then
		vim.notify("Clipboard is empty", vim.log.levels.INFO)
		return
	end

	local dest_dir_node = resolve_destination_dir_node()

  -- stylua: ignore
	if not dest_dir_node then return end

	---@type Beast.Explorer.PasteSession
	local session = PasteSession({
		paths = state.clipboard.paths,
		mode = state.clipboard.mode,
		dest_dir_node = dest_dir_node,
	})

	ensure_destination_open(dest_dir_node, function()
		session:start()
	end)
end

return M
