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
	local submodules =
		{ "config", "repo", "diff", "hunks", "signs", "patch", "apply", "actions", "nav", "preview", "blame", "current_line_blame", "blame_view" }
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

	-- Namespaces
	health.start("beast.libs.git — namespaces")
	local signs = require("beast.libs.git.signs")
	local nss = vim.api.nvim_get_namespaces()
	local id_to_name = {}
	for name, id in pairs(nss) do
		id_to_name[id] = name
	end
	for kind, ns_id in pairs(signs.namespaces) do
		local name = id_to_name[ns_id]
		if name then
			health.ok(("namespace registered (%s): %s"):format(kind, name))
		else
			health.warn(("namespace not resolved by name (%s) — setup not yet called?"):format(kind))
		end
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
		health.info("default keymaps disabled — bind nav_hunk / preview_hunk / stage_hunk / reset_hunk manually")
	end

	-- Statuscolumn highlight groups for staged tier (Phase 2/3 contract).
	health.start("beast.libs.git — staged-tier highlights")
	for _, hl in ipairs({ "BeastStcGitStagedAdd", "BeastStcGitStagedChange", "BeastStcGitStagedDelete" }) do
		local ok, attrs = pcall(vim.api.nvim_get_hl, 0, { name = hl })
		if ok and attrs and (attrs.fg or attrs.link) then
			health.ok(hl .. " defined")
		else
			health.warn(hl .. " not defined — statuscolumn theme not loaded yet?")
		end
	end

	-- Blame
	health.start("beast.libs.git — blame")
	local cfg = require("beast.libs.git.config")
	health.info(
		string.format(
			"current-line blame: %s (delay_ms=%d, pos=%s)",
			cfg.blame.enabled and "enabled" or "disabled",
			cfg.blame.delay_ms,
			cfg.blame.virt_text_pos
		)
	)
	-- user.name — synchronous probe (health checks are allowed to block briefly).
	local result = vim.system({ "git", "config", "user.name" }, { text = true }):wait()
	local username = vim.trim(result.stdout or "")
	if result.code == 0 and username ~= "" then
		health.ok("git config user.name = " .. username)
	else
		health.warn("git config user.name is unset — blame formatter will not substitute 'You'")
	end
end
