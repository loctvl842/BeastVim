local Picker = require("beast.libs.finder.picker")
local config = require("beast.libs.finder.config")
local highlights = require("beast.libs.finder.highlights")

local _picker = nil ---@type Beast.Finder.Picker|nil
local _augroup = nil

local M = {}

local function ensure_autocmds()
	if _augroup then
		return
	end
	_augroup = vim.api.nvim_create_augroup("BeastFinder", { clear = true })
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = _augroup,
		callback = highlights.setup,
	})
end

---@param opts? Beast.Finder.Config
function M.setup(opts)
	config.setup(opts)
	highlights.setup()
	ensure_autocmds()

	-- Override vim.ui.select
	vim.ui.select = function(items, ui_opts, on_choice)
		local prompt = (ui_opts and ui_opts.prompt) or "Select"
		local fmt = (ui_opts and ui_opts.format_item) or tostring

		local finder_items = {}
		for i, v in ipairs(items) do
			finder_items[i] = { idx = i, score = 0, text = fmt(v), _value = v }
		end

		M.open("_select", {
			_items = finder_items,
			_prompt = prompt,
			action = function(_, selected)
				local item = selected[1]
				on_choice(item and item._value or nil, item and item.idx or nil)
			end,
		})
	end
end

---@param source_name string "files"|"buffers"|"_select"
---@param opts? table
function M.open(source_name, opts)
	M.close()
	_picker = Picker.new(source_name, opts)
end

function M.close()
	if _picker then
		_picker:close()
		_picker = nil
	end
end

return M
