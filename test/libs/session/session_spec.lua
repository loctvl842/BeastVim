local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

-- Session lib: save guard, branch naming, load fallback, exists(), explorer sidecar.
t.describe("session", function()
	t.before_each(function()
		h.clear()
		n.exec_lua(function()
			-- Collaborators the explorer reaches for (outside this lib's scope).
			_G.Toast = function(...) end
			package.loaded["nvim-web-devicons"] = {
				get_icon = function()
					return "󰈙", "DevIconDefault"
				end,
			}

			local root = vim.fn.tempname()
			vim.fn.mkdir(root, "p")
			_G.root = root
			_G.sessions_dir = root .. "/sessions/"

			--- Run a shell command in `dir`, asserting it succeeds.
			_G.sh = function(dir, cmd)
				local result = vim.system({ "sh", "-c", cmd }, { cwd = dir }):wait()
				assert(result.code == 0, "command failed: " .. cmd .. "\n" .. (result.stderr or ""))
			end

			--- Same encoding rule the lib uses internally.
			_G.encode = function(s)
				return (s:gsub("[\\/:]+", "%%"))
			end

			_G.wipe_buffers = function()
				vim.cmd("silent! %bwipeout!")
			end

			--- Fire the VimLeavePre autocmd session.setup() registered, synchronously.
			_G.trigger_save = function()
				vim.api.nvim_exec_autocmds("VimLeavePre", {})
			end

			--- Basenames of all currently open named buffers, sorted.
			_G.open_buffer_names = function()
				local names = {}
				for _, buf in ipairs(vim.api.nvim_list_bufs()) do
					local name = vim.api.nvim_buf_get_name(buf)
					if name ~= "" then
						names[#names + 1] = vim.fn.fnamemodify(name, ":t")
					end
				end
				table.sort(names)
				return names
			end

			--- git repo `name` under root on branch main, with the given files, chdir'd into.
			---@return string cwd resolved (macOS /tmp -> /private/tmp)
			_G.make_repo = function(name, files)
				local dir = root .. "/" .. name
				vim.fn.mkdir(dir, "p")
				_G.sh(dir, "git init -q && git checkout -q -b main")
				for path, content in pairs(files) do
					vim.fn.mkdir(vim.fn.fnamemodify(dir .. "/" .. path, ":h"), "p")
					vim.fn.writefile({ content }, dir .. "/" .. path)
				end
				_G.sh(dir, "git add -A && git commit -q -m init")
				vim.fn.chdir(dir)
				return vim.fn.getcwd()
			end

			_G.session = require("beast.libs.session")
			_G.session.setup({ dir = _G.sessions_dir })
		end)
	end)

	t.after_each(function()
		n.exec_lua("vim.fn.delete(_G.root, 'rf')")
	end)

	t.describe("save guard", function()
		t.it("writes no session file with 0 real buffers", function()
			t.eq(
				true,
				n.exec_lua(function()
					local cwd = _G.make_repo("repo", { ["a.lua"] = "a" })
					_G.wipe_buffers()
					vim.cmd("enew") -- unnamed scratch buffer only
					_G.trigger_save()
					return vim.uv.fs_stat(_G.sessions_dir .. _G.encode(cwd) .. ".vim") == nil
				end)
			)
		end)
	end)

	t.describe("main branch (no suffix)", function()
		t.before_each(function()
			n.exec_lua(function()
				_G.cwd = _G.make_repo("repo", { ["a.lua"] = "a", ["b.lua"] = "b" })
				_G.plain_path = _G.sessions_dir .. _G.encode(_G.cwd) .. ".vim"
				_G.wipe_buffers()
				vim.cmd("edit a.lua")
				vim.cmd("split b.lua")
				_G.trigger_save()
			end)
		end)

		t.it("writes the plain session file and exists() is true", function()
			t.eq(
				{ file = true, exists = true },
				n.exec_lua(function()
					return { file = vim.uv.fs_stat(_G.plain_path) ~= nil, exists = _G.session.exists() }
				end)
			)
		end)

		t.it("load() restores a.lua and b.lua", function()
			t.eq(
				{ "a.lua", "b.lua" },
				n.exec_lua(function()
					_G.wipe_buffers()
					_G.session.load()
					return _G.open_buffer_names()
				end)
			)
		end)
	end)

	t.describe("feature branch", function()
		t.before_each(function()
			n.exec_lua(function()
				_G.cwd = _G.make_repo("repo", { ["a.lua"] = "a", ["b.lua"] = "b" })
				_G.plain_path = _G.sessions_dir .. _G.encode(_G.cwd) .. ".vim"
				_G.wipe_buffers()
				vim.cmd("edit a.lua")
				vim.cmd("split b.lua")
				_G.trigger_save()
				_G.main_mtime = vim.uv.fs_stat(_G.plain_path).mtime.sec
				_G.sh(_G.cwd, "git checkout -q -b feature/login")
				_G.wipe_buffers()
				vim.cmd("edit a.lua")
				_G.trigger_save()
			end)
		end)

		t.it("gets its own session file and leaves main's untouched", function()
			t.eq(
				{ branch_file = true, main_untouched = true },
				n.exec_lua(function()
					local branch_path = _G.sessions_dir .. _G.encode(_G.cwd) .. "%%" .. _G.encode("feature/login") .. ".vim"
					return {
						branch_file = vim.uv.fs_stat(branch_path) ~= nil,
						main_untouched = vim.uv.fs_stat(_G.plain_path).mtime.sec == _G.main_mtime,
					}
				end)
			)
		end)

		t.it("load() restores only its own session", function()
			t.eq(
				{ "a.lua" },
				n.exec_lua(function()
					_G.wipe_buffers()
					_G.session.load()
					return _G.open_buffer_names()
				end)
			)
		end)

		t.it("a new branch with no session falls back to the plain session", function()
			t.eq(
				{ exists = true, names = { "a.lua", "b.lua" } },
				n.exec_lua(function()
					_G.sh(_G.cwd, "git checkout -q -b feature/new-thing")
					local exists = _G.session.exists()
					_G.wipe_buffers()
					_G.session.load()
					return { exists = exists, names = _G.open_buffer_names() }
				end)
			)
		end)
	end)

	t.describe("non-git directory", function()
		t.before_each(function()
			n.exec_lua(function()
				local dir = _G.root .. "/plain"
				vim.fn.mkdir(dir, "p")
				_G.sh(dir, "printf 'c' > c.lua")
				vim.fn.chdir(dir)
				_G.cwd = vim.fn.getcwd()
				_G.wipe_buffers()
				vim.cmd("edit c.lua")
				_G.trigger_save()
			end)
		end)

		t.it("gets a plain session file and never a %%branch-suffixed one", function()
			t.eq(
				{ plain = true, suffixed = 0 },
				n.exec_lua(function()
					return {
						plain = vim.uv.fs_stat(_G.sessions_dir .. _G.encode(_G.cwd) .. ".vim") ~= nil,
						suffixed = #vim.fn.glob(_G.sessions_dir .. _G.encode(_G.cwd) .. "%%*.vim", true, true),
					}
				end)
			)
		end)

		t.it("load() restores c.lua", function()
			t.eq(
				{ "c.lua" },
				n.exec_lua(function()
					_G.wipe_buffers()
					_G.session.load()
					return _G.open_buffer_names()
				end)
			)
		end)
	end)

	t.describe("no session anywhere", function()
		t.before_each(function()
			n.exec_lua(function()
				_G.make_repo("empty-repo", { ["x.lua"] = "x" })
			end)
		end)

		t.it("exists() is false", function()
			t.eq(false, n.exec_lua("return _G.session.exists()"))
		end)

		t.it("load() does not error and is a true no-op", function()
			t.eq(
				{ ok = true, bufs = 1 },
				n.exec_lua(function()
					_G.wipe_buffers()
					local ok = pcall(_G.session.load)
					return { ok = ok, bufs = #vim.api.nvim_list_bufs() }
				end)
			)
		end)
	end)

	t.describe("explorer state", function()
		t.before_each(function()
			n.exec_lua(function()
				_G.explorer = require("beast.libs.explorer")
				_G.explorer_state = require("beast.libs.explorer.state")
			end)
		end)

		t.it("restores open + expanded folders + focus=explorer", function()
			t.eq(
				{ sidecar = true, root = true, src = true, tests = true, focus = true },
				n.exec_lua(function()
					local cwd = _G.make_repo("explorer-a", { ["src/components/button.lua"] = "return {}", ["tests/x.lua"] = "x" })
					_G.explorer.close()
					_G.wipe_buffers()
					vim.cmd("edit " .. vim.fn.fnameescape(cwd .. "/src/components/button.lua"))
					_G.explorer.open(cwd)
					local state = _G.explorer_state
					state.tree:open(cwd .. "/src/components")
					state.tree:open(cwd .. "/tests")
					_G.trigger_save()
					local sidecar = vim.uv.fs_stat(_G.sessions_dir .. _G.encode(cwd) .. ".explorer.json") ~= nil

					_G.wipe_buffers()
					_G.session.load()
					state = _G.explorer_state
					local nodes = state.tree and state.tree.nodes
					return {
						sidecar = sidecar,
						root = state.tree ~= nil and state.tree.root.path == cwd,
						src = nodes[cwd .. "/src"] ~= nil and nodes[cwd .. "/src"].open == true,
						tests = nodes[cwd .. "/tests"] ~= nil and nodes[cwd .. "/tests"].open == true,
						focus = state.view ~= nil and vim.api.nvim_get_current_win() == state.view.win,
					}
				end)
			)
		end)

		t.it("restores focus=main to the last edited file", function()
			t.eq(
				{ root = true, not_explorer = true, file = "main.lua" },
				n.exec_lua(function()
					local cwd = _G.make_repo("explorer-b", { ["src/main.lua"] = "return {}" })
					_G.explorer.close()
					_G.wipe_buffers()
					vim.cmd("edit " .. vim.fn.fnameescape(cwd .. "/src/main.lua"))
					_G.explorer.open(cwd)
					_G.explorer_state.tree:open(cwd .. "/src")
					-- Like a user who browsed the explorer and clicked back into their file.
					vim.api.nvim_set_current_win(_G.explorer_state.source_win)
					_G.trigger_save()

					_G.wipe_buffers()
					_G.session.load()
					local state = _G.explorer_state
					return {
						root = state.tree ~= nil and state.tree.root.path == cwd,
						not_explorer = state.view ~= nil and vim.api.nvim_get_current_win() ~= state.view.win,
						file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t"),
					}
				end)
			)
		end)

		t.it("keeps a closed explorer closed and clears a stale sidecar", function()
			t.eq(
				{ written = true, cleared = true, closed = true, names = { "keep.lua" } },
				n.exec_lua(function()
					local cwd = _G.make_repo("explorer-c", { ["keep.lua"] = "note" })
					local sidecar = _G.sessions_dir .. _G.encode(cwd) .. ".explorer.json"
					_G.explorer.close()
					_G.wipe_buffers()
					vim.cmd("edit keep.lua")
					_G.explorer.open(cwd)
					_G.trigger_save()
					local written = vim.uv.fs_stat(sidecar) ~= nil

					-- The first save closed the explorer; a second save must clear the
					-- now-stale sidecar rather than leave it pointing at open state.
					_G.trigger_save()
					local cleared = vim.uv.fs_stat(sidecar) == nil

					_G.wipe_buffers()
					_G.session.load()
					local view = _G.explorer_state.view
					return {
						written = written,
						cleared = cleared,
						closed = not view or not view:is_valid(),
						names = _G.open_buffer_names(),
					}
				end)
			)
		end)

		t.it("fails silently when the saved explorer root was deleted", function()
			t.eq(
				{ rooted = true, sidecar = true, ok = true, closed = true, names = { "keep.lua" } },
				n.exec_lua(function()
					local cwd = _G.make_repo("explorer-d", { ["legacy/y.lua"] = "y", ["keep.lua"] = "note" })
					local legacy_root = cwd .. "/legacy"
					_G.explorer.close()
					_G.wipe_buffers()
					vim.cmd("edit keep.lua")
					-- opts.restore=true only forces the exact root for a deterministic setup.
					_G.explorer.open(legacy_root, { restore = true })
					local rooted = _G.explorer_state.tree.root.path == legacy_root
					_G.trigger_save()
					local sidecar = vim.uv.fs_stat(_G.sessions_dir .. _G.encode(cwd) .. ".explorer.json") ~= nil

					vim.fn.delete(legacy_root, "rf")
					_G.wipe_buffers()
					local ok = pcall(_G.session.load)
					local view = _G.explorer_state.view
					return {
						rooted = rooted,
						sidecar = sidecar,
						ok = ok,
						closed = not view or not view:is_valid(),
						names = _G.open_buffer_names(),
					}
				end)
			)
		end)
	end)
end)
