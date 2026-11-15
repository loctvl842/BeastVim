--- The picker: its windows, keys and autocmds, and a stack of levels (searches) shown in them.
--- One session exists at a time. `push` puts a new level in the same windows (the current one is
--- remembered), `pop` brings the previous one back exactly as it was, without searching again.
local Level = require("beast.libs.finder.level")
local View = require("beast.libs.view")
local config = require("beast.libs.finder.config")
local ui = require("beast.libs.finder.ui")

---@class Beast.Finder.View
---@field input Beast.Finder.InputView
---@field list Beast.Finder.ListView
---@field preview? Beast.Finder.PreviewView
---@field backdrop? Beast.Finder.BackdropView
---@field hint Beast.Finder.HintView key hints under the picker

---@class Beast.Finder.Session
---@field id integer
---@field closed boolean -- guards against double-close (stale picker re-closed on next open)
---@field level Beast.Finder.Level the level shown now
---@field stack Beast.Finder.Level[] levels pushed under it, the nearest last
---@field view? Beast.Finder.View
---@field on_preview? fun(item: Beast.Finder.Item)
---@field on_close? fun(confirmed: boolean)
---@field confirmed? boolean the picker is closing because the user confirmed an item (Enter)
---@field layout? "cards"
---@field initial_text? string
---@field initial_done? boolean the initial selection has been applied
---@field echo? string prompt text this session wrote itself; the first change event for the same text is skipped (its search already ran or is not wanted)
---@field frozen? boolean panels use frozen highlight namespaces
---@field main_win? integer
---@field augroup? integer
local M = {}
M.__index = M

---@type Beast.Finder.Session?
local instance
local last_id = 0

---@class Beast.Finder.Opts: Beast.Finder.LevelOpts
---@field on_preview? fun(item: Beast.Finder.Item)
---@field on_close? fun(confirmed: boolean) called once the picker is gone; `confirmed` is true after Enter
---@field preview? boolean preview window enabled
---@field layout? "cards" separate prompt/list boxes
---@field separators? boolean separator rows between list items
---@field backdrop? boolean false skips the dimming overlay (default true)
---@field initial_text? string start with the item whose text matches selected (instead of the first one)
---@field freeze_colors? boolean keep the panels in the colors they had at open, ignoring `:colorscheme`

--- How a level reaches this session's windows. Every method is a no-op once the level is no
--- longer the one shown, so a late answer of a replaced or popped level cannot draw anything.
---@param session Beast.Finder.Session
---@param level Beast.Finder.Level
---@return Beast.Finder.Host
local function make_host(session, level)
	local render = require("beast.libs.finder.render")
	local function current()
		return not session.closed and session.level == level and session.view ~= nil and session.view.list:is_valid()
	end
	return {
		alive = current,
		render = function()
			if current() then
				render.render(session)
			end
		end,
		busy = function(on)
			if current() then
				if on then
					ui.input.start_spinner(session.view.input)
				else
					ui.input.stop_spinner(session.view.input)
				end
			end
		end,
		rewind = function()
			if current() then
				session.view.list.cursor = 1
				session.view.list._offset = 0
			end
		end,
		count = function(text)
			level.count = text
			if current() then
				ui.input.set_count(session.view.input, text)
			end
		end,
		title = function(text)
			level.title = text
			-- The cards layout has no title.
			if current() and session.layout ~= "cards" then
				ui.input.set_title(session.view.input, text)
			end
		end,
		rows = function()
			return session.view and session.view.list._win_height or 50
		end,
	}
end

--- Open the picker on `source_name`, replacing any picker that is open.
---@param source_name Beast.Finder.Source
---@param opts? Beast.Finder.Opts
---@return Beast.Finder.Session
function M.open(source_name, opts)
	opts = opts or {}
	M.close_current()

	local level = Level.new(source_name, opts)
	last_id = last_id + 1
	local session = setmetatable({
		id = last_id,
		closed = false,
		main_win = View.win.find_normal(),
		on_preview = opts.on_preview,
		on_close = opts.on_close,
		layout = opts.layout,
		initial_text = opts.initial_text,
		frozen = opts.freeze_colors,
		level = level,
		stack = {},
	}, M)
	instance = session

	-- View
	local has_preview = opts.preview ~= false
	local geo = require("beast.libs.finder.layout").calc(has_preview, opts.layout)
	local title = opts.layout == "cards" and "" or level.title
	local frozen = opts.freeze_colors and require("beast.libs.finder.highlights").freeze() or nil

	session.view = {
		input = ui.input.create(
			function(text)
				-- Writing the prompt ourselves can echo back as a change event; that search already ran.
				if session.echo and text == session.echo then
					session.echo = nil
					return
				end
				session.echo = nil
				session.level:run(text)
			end,
			geo.input.w,
			geo.input.h,
			geo.input.row,
			geo.input.col,
			title,
			session.level.debounce_ms,
			geo.input.border,
			opts.layout == "cards",
			level.initial_query
		),
		list = ui.list.create(geo.list.row, geo.list.col, geo.list.w, geo.list.h, geo.list.border, opts.separators),
		backdrop = opts.backdrop ~= false and ui.backdrop.create(config.backdrop) or nil,
		hint = ui.hint.create(),
	}
	if frozen then
		vim.api.nvim_win_set_hl_ns(session.view.input.win, frozen.input)
		vim.api.nvim_win_set_hl_ns(session.view.list.win, frozen.list)
	end
	if has_preview then
		session.view.preview = ui.preview.create(geo.preview.row, geo.preview.col, geo.preview.w, geo.preview.h)
	end

	-- The prompt was created with the level's opening text already in it.
	level.host = make_host(session, level)
	session.echo = level.initial_query
	-- Match pipeline loads items immediately; stream waits for user input, except a live
	-- source with a default query, which searches right away.
	level:start()

	require("beast.libs.finder.keymaps").mount(session)
	require("beast.libs.finder.autocmds").mount(session)
	return session
end

--- Close the open picker, if any.
function M.close_current()
	if instance then
		instance:close()
	end
end

--- The open picker, if any.
---@return Beast.Finder.Session?
function M.current()
	return instance
end

--- Remember where the list is, so the level can be shown again.
function M:_leave()
	local level = self.level
	level.cursor = self.view.list.cursor
	level.offset = self.view.list._offset
	-- What is in the prompt now (a typed change may still be waiting out its debounce).
	level.text = ui.input.get_text(self.view.input)
	ui.input.stop_spinner(self.view.input)
	require("beast.libs.finder.render").cleanup(level.query)
end

--- Put `level`'s prompt, title, count and list position into the windows.
---@param level Beast.Finder.Level
---@param text string prompt text to show
function M:_enter(level, text)
	local input = self.view.input
	self.echo = text
	ui.input.set_text(input, text)
	if self.layout ~= "cards" then
		ui.input.set_title(input, level.title)
	end
	ui.input.set_count(input, level.count)
	ui.input.set_debounce(input, level.debounce_ms)
	-- A level that was still working when it was left (or is popped back to) shows its spinner again.
	if level.query.loading then
		ui.input.start_spinner(input)
	end
	self.view.list.cursor = level.cursor
	self.view.list._offset = level.offset
end

--- Show `level` in the windows. The current level is remembered and comes back with `pop`.
--- Push from a level that has finished working: answers a running search delivers while it is
--- not the shown level are dropped.
---@param level Beast.Finder.Level
function M:push(level)
	-- stylua: ignore
	if self.closed then return end
	self:_leave()
	self.stack[#self.stack + 1] = self.level
	self.level = level
	level.host = make_host(self, level)
	self:_enter(level, level.initial_query or "")
	-- Draw the empty level now, so nothing of the previous one (rows, preview) lingers until its results arrive.
	require("beast.libs.finder.render").render(self)
	level:start()
end

--- Bring the previous level back as it was left (prompt, results, cursor, scroll), without searching.
---@return boolean popped false when there is no previous level
function M:pop()
	local parent = table.remove(self.stack)
	-- stylua: ignore
	if self.closed or not parent then return false end
	local child = self.level
	self:_leave()
	child:stop()
	self.level = parent
	self:_enter(parent, parent.text)
	require("beast.libs.finder.render").render(self)
	return true
end

function M:close()
	if self.closed then
		return
	end
	-- Mark closed up front. Closing the windows below synchronously fires
	-- WinEnter/WinClosed autocmds that call close() again; the guard above
	-- turns those re-entrant calls into no-ops so M.view is not nilled mid-cleanup.
	self.closed = true
	local render = require("beast.libs.finder.render")
	if self.view then
		require("beast.libs.finder.ui.input").stop_spinner(self.view.input)
		-- Erase any inline image before closing windows: image.clear() clips its
		-- erase rect to the preview window's current bounds, so it must run while
		-- that window is still valid (Kitty placements persist past window close;
		-- no-op for the iTerm2 protocol).
		if self.view.preview and self.view.preview.loaded_image then
			require("beast.libs.image").clear()
		end
		ui.hint.close(self.view.hint)
		self.view.input:close()
		self.view.list:close()
		if self.view.preview then
			self.view.preview:close()
		end
		if self.view.backdrop then
			self.view.backdrop:close()
		end
	end
	if self.frozen then
		require("beast.libs.finder.highlights").unfreeze()
	end
	for _, level in ipairs(self.stack) do
		level:stop()
		render.cleanup(level.query)
	end
	self.level:stop()
	render.cleanup(self.level.query)
	if self.main_win and vim.api.nvim_win_is_valid(self.main_win) then
		vim.api.nvim_set_current_win(self.main_win)
	end
	if self.augroup then
		pcall(vim.api.nvim_del_augroup_by_id, self.augroup)
	end
	if instance == self then
		instance = nil
	end
	-- Last, so an on_close that opens another picker finds this one completely gone (its windows
	-- closing would otherwise move focus and close the new picker).
	if self.on_close then
		self.on_close(self.confirmed == true)
	end
end

function M:relayout()
  -- stylua: ignore
  if not self.view then return end
	local render = require("beast.libs.finder.render")

	local geo = require("beast.libs.finder.layout").calc(self.view.preview ~= nil, self.layout)

	-- Reposition backdrop
	if self.view.backdrop and self.view.backdrop:is_valid() then
		pcall(vim.api.nvim_win_set_config, self.view.backdrop.win, {
			relative = "editor",
			width = vim.o.columns,
			height = vim.o.lines,
			row = 0,
			col = 0,
		})
	end

	-- Reposition input
	if self.view.input:is_valid() then
		pcall(vim.api.nvim_win_set_config, self.view.input.win, {
			relative = "editor",
			width = geo.input.w,
			height = geo.input.h,
			row = geo.input.row,
			col = geo.input.col,
		})
	end

	-- Reposition list
	if self.view.list:is_valid() then
		pcall(vim.api.nvim_win_set_config, self.view.list.win, {
			relative = "editor",
			width = geo.list.w,
			height = geo.list.h,
			row = geo.list.row,
			col = geo.list.col,
		})
	end

	-- Reposition preview
	if self.view.preview and self.view.preview:is_valid() then
		pcall(vim.api.nvim_win_set_config, self.view.preview.win, {
			relative = "editor",
			width = geo.preview.w,
			height = geo.preview.h,
			row = geo.preview.row,
			col = geo.preview.col,
		})
		-- Re-draw the inline image (if any) at the new geometry; VimResized
		-- triggers a full repaint that would otherwise erase it.
		require("beast.libs.finder.ui.preview").refresh(self.view.preview)
	end

	render.hint(self)

	-- Separator rows are as wide as the list window, so redraw them at the new width
	if self.view.list._separators then
		render.render(self)
	end
end

return M
