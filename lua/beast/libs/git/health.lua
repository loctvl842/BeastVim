local M = {}

function M.check()
	local health = vim.health

	health.start("beast.libs.git")

	if vim.fn.executable("git") == 1 then
		health.ok("`git` executable found")
	else
		health.error("`git` not found in PATH — library cannot resolve repos")
		return
	end

	if vim.fn.has("nvim-0.10") == 1 then
		health.ok("Neovim >= 0.10")
	else
		health.error("Neovim 0.10+ required (extmark `sign_text` API)")
	end

	-- Submodules (avoid `highlights` — requiring it executes side-effecting set_hl).
	health.start("beast.libs.git — modules")
	local submodules = { "config", "repo", "diff", "hunks", "signs" }
	for _, name in ipairs(submodules) do
		local ok, err = pcall(require, "beast.libs.git." .. name)
		if ok then
			health.ok("loaded: " .. name)
		else
			health.error(string.format("failed to load %s: %s", name, err))
		end
	end

	-- Diff backend
	health.start("beast.libs.git — diff backend")
	local diff = require("beast.libs.git.diff")
	health.info("backend: " .. diff.backend)

	-- Namespace
	health.start("beast.libs.git — namespace")
	local signs = require("beast.libs.git.signs")
	local nss = vim.api.nvim_get_namespaces()
	local found = false
	for name, id in pairs(nss) do
		if id == signs.namespace then
			found = true
			health.ok("namespace registered: " .. name)
			break
		end
	end
	if not found then
		health.warn("namespace registered but no name resolved (setup not yet called?)")
	end

	-- Attached buffers + last-diff timing
	health.start("beast.libs.git — attached buffers")
	local git = require("beast.libs.git")
	local count = 0
	local samples = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		local st = git._get_state(buf)
		if st then
			count = count + 1
			if st.last_diff_ms then
				samples[#samples + 1] = st.last_diff_ms
			end
		end
	end
	health.info(string.format("attached: %d buffer(s)", count))
	if #samples > 0 then
		local total = 0
		for _, v in ipairs(samples) do
			total = total + v
		end
		health.info(string.format("last-diff mean: %.2f ms across %d buffer(s)", total / #samples, #samples))
	end
	-- Preview availability
	health.start("beast.libs.git — preview")
	local ok_view, _ = pcall(require, "beast.libs.view")
	if ok_view then
		health.ok("Beast.View base class loadable")
	else
		health.error("Beast.View base class missing — preview cannot open")
	end
	if require("beast.libs.git.config").keymaps then
		health.info("default keymaps enabled: ]c, [c, <leader>gp (buffer-local on attach)")
	else
		health.info("default keymaps disabled — bind nav_hunk / preview_hunk manually")
	end
end
