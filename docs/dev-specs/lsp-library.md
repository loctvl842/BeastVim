# Dev Spec: LSP Library

> **Status:** ✅ Completed 2026-06-08 (Phase 1 + Phase 2 shipped, ADRs 029–031 written).

## Summary

Build a `beast/libs/lsp/` library that wraps Neovim 0.12's builtin LSP client (`vim.lsp.config`, `vim.lsp.enable`, `LspAttach`) into a thin **infrastructure** layer. The library owns *policy* — diagnostics config, capabilities composition, the global `LspAttach` pipeline, and a `register(name, cfg)` API — but does **not** own server-specific knowledge (that lives in future `lang` extensions, see *Out of Scope*). **No dependency on `nvim-lspconfig` or `mason-lspconfig`.**

This is the same pattern as `beast/libs/treesitter/` (thin wrapper over builtin) and follows the same `setup → enable → per-attach handler` shape.

## Requirements

- Public API:
  - `lsp.setup(opts)` — initialize diagnostics, register global `LspAttach` handler, install user commands
  - `lsp.register(name, cfg)` — declare a server config; merges into `vim.lsp.config(name, ...)` and calls `vim.lsp.enable(name)`
  - `lsp.capabilities()` — returns merged client capabilities (base + completion plugin contributions)
  - `lsp.add_capabilities(tbl_or_fn)` — extension point for completion plugins (blink.cmp, nvim-cmp) to contribute caps
  - `lsp.on_attach(fn)` — register an additional buffer-local handler that runs on every `LspAttach`
- `register(name, cfg)` accepts the full `vim.lsp.Config` shape plus BeastVim extensions:
  - `keys` — list of `{lhs, rhs, desc, mode?, group?}` entries; bound as **buffer-local** keymaps when this specific server attaches
  - `on_attach(client, bufnr)` — per-server hook, runs alongside global handlers
- Global `LspAttach` handler:
  - Looks up per-server config registered via `lsp.register`
  - Applies per-server `keys` (buffer-local) and per-server `on_attach`
  - Runs subscribers from `lsp.on_attach(fn)` in registration order
  - Gates feature-specific keys on `client:supports_method()`
- Diagnostics config applied at `setup()` time: signs, virtual_text policy, severity sort, float border — following BeastVim visual conventions (palette-driven, see `beast/setup/highlights.lua` integration in adjacent libs).
- Health check (`:checkhealth beast.libs.lsp`):
  - List enabled configs (via `vim.lsp.config._configs` or `vim.lsp.get_clients()`)
  - List attached clients per current buffer
  - Show any registration errors
- Lazy-loadable via `packer.lazy("beast.libs.lsp", { event = ... })` — same shape as `treesitter`/`git`.
- Follow BeastVim library conventions: § *Config Pattern* (defaults + live cfg + `setup`), § *State Ownership* (the lib owns the `LspAttach` augroup and the subscriber/register tables), § *File Structure* (one module per concern).

## Out of Scope

- **Lang extension manager (`beast/libs/lang/`).** Separate spec — handles `vim.pack.add` of `BeastVim/<Lang>` repos, FileType-triggered install prompts, `ctx` plumbing.
- **Per-language server configs.** No `lua_ls`/`vtsls`/etc. tables in this lib. Phase 1 verification uses one hand-wired server *outside* the lib code.
- **Formatter library (`beast/libs/format/`).** Separate spec — conform.nvim wrapper. This lib does not call `vim.lsp.buf.format` from a `BufWritePre` autocmd. The future `format` lib will call `lsp.format(buf, client_id)` as a fallback source.
- **Mason wrapper (`beast/libs/mason/`).** Separate spec.
- **Treesitter** — already exists (`beast/libs/treesitter/`).
- **Completion plugin integration.** The `add_capabilities()` hook exists, but actually wiring blink.cmp / nvim-cmp is a downstream spec.
- **Wrapping `:lsp restart` / `:lsp stop`.** Neovim 0.12 already ships these — do not re-implement.
- **`Util.lsp.execute` / `Util.lsp.action` wrappers.** Lang extensions call `vim.lsp.buf_request`, `vim.lsp.buf.execute_command`, and `vim.lsp.buf.code_action` directly. No intermediate abstraction layer over the native `vim.lsp.*` API.
- **Overriding Neovim 0.12 default global LSP keymaps** (`K`, `gd`, `grr`, `gri`, `grn`, `gra`, `grt`, `<C-S>`, `[d`, `]d`). Documented as native behavior.
- **Inlay hints / codelens UX toggles.** Add in a follow-up spec once base lib is stable.
- **Semantic token highlight customization.** Out of scope for this lib (handled by colorscheme/highlights).

## Research

### Repo Search

- Searched for: `vim.lsp`, `LspAttach`, `on_attach`, `vim.lsp.config`, `vim.lsp.enable`, `register`
- Found:
  - `lua/beast/util/root.lua:62-92` — `M.detectors.lsp(buf)` reads `vim.lsp.get_clients({ bufnr })` for root detection. **Already a consumer of LSP state.** No conflict with this lib; root detector will keep working unchanged.
  - `lua/beast/util/root.lua:367` — autocmd already listens on `LspAttach` for cache invalidation. New lib must use a separate `augroup` (`BeastVim-lsp`) to avoid clearing the root cache hook.
  - `lua/beastvim/plugins/lang/*.lua` (legacy `~/.config/nvim/`, not BeastVim) — reference implementations using `mason.nvim` opts-merging for `servers = { ... }`. **The `register(name, cfg)` API is the BeastVim-native replacement for that opts-merging pattern.**
  - `lua/beast/libs/treesitter/` — closest sibling pattern: builtin-API wrapper with `init.lua` / `config.lua` / `health.lua` / `enable()` flow. **Adopt the same shape.**
  - `lua/beast/libs/git/`, `lua/beast/libs/explorer/` — pattern for `setup(opts)` + autocmd-driven activation. **Adopt the same shape.**
- Reuse opportunity:
  - **Adopt** `beast/libs/treesitter/` as the structural template (config/init/health split, lazy-loaded via `packer.lazy`).
  - **Adopt** `Util.root` (`beast/util/root.lua`) — when a server's `root_markers` is nil, fall back to `Util.root.get({ buf })`. This unifies root resolution across the editor.
  - **Adopt** `Key.safe_set` (`beast/libs/key/`) — use it for buffer-local keymaps applied during `LspAttach` so they appear in the cheatsheet.
  - **No existing code covers** the `register(name, cfg)` orchestration, the per-server keymap binding, or the capabilities-composition hook — these must be built.

### Package Search

- Searched: Neovim 0.12.2 native LSP API (`:help lsp`), confirmed at `nvim --version` → `NVIM v0.12.2`. Fetched `https://neovim.io/doc/user/lsp/`.
- Found:
  - `vim.lsp.config(name, cfg)` — define/extend server config; deep-merges with `lsp/<name>.lua` and `after/lsp/<name>.lua` files on runtimepath.
  - `vim.lsp.enable(name)` — wire a config to start automatically on matching `filetypes`; supersedes calling `vim.lsp.start()` manually.
  - `vim.lsp.protocol.make_client_capabilities()` — base client caps.
  - `LspAttach` autocmd with `ev.data.client_id` — the canonical post-attach hook.
  - `client:supports_method(method)` — capability gate for keymap registration.
  - `client:request()`, `client:request_sync()`, `vim.lsp.util.make_position_params()` — needed by `Util.lsp.execute` helper.
  - Global keymaps (`K`, `gd`, `grr`, `gri`, `grn`, `gra`, `grt`, `<C-S>`, `[d`, `]d`) are **already wired by Neovim 0.12 on LSP attach** — must not override blindly.
  - `:lsp restart [name]`, `:lsp stop [name]` — built-in user commands; do not wrap.
  - Config merge precedence: `*` → `lsp/<name>.lua` (rtp) → `after/lsp/<name>.lua` → direct `vim.lsp.config(name, ...)` calls (last write wins via `vim.tbl_deep_extend("force", ...)`).
- Decision: **Use native** — every primitive needed exists in core. The lib is a *policy + ergonomics* layer over `vim.lsp.config` + `vim.lsp.enable` + `LspAttach`. Zero plugins.

### nvim-lspconfig / mason-lspconfig comparison

| What nvim-lspconfig provides | Neovim 0.12 / this lib equivalent |
|---|---|
| `lspconfig.<server>.setup{}` machinery | `vim.lsp.config(name, cfg)` + `vim.lsp.enable(name)` (core) |
| Server default configs (cmd, filetypes, root_dir) | Provided per-server by `BeastVim/<Lang>` extensions (future) |
| Auto-`vim.lsp.start()` on FileType | `vim.lsp.enable()` does this in core |
| `on_attach`/`capabilities` plumbing | `lsp.register()` accepts these; global `LspAttach` runs them |
| `mason-lspconfig` name bridging | Per-server `mason_packages` in lang ext manifest (future) |

The plugin's catalog of default configs is the only remaining value, and that responsibility moves to `BeastVim/<Lang>` extension repos. The lib itself ships with zero servers.

## Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/libs/lsp/init.lua` | Create | Public API: `setup`, `register`, `capabilities`, `add_capabilities`, `on_attach` |
| `lua/beast/libs/lsp/config.lua` | Create | Defaults + live cfg + `setup(opts)` merge (§ Config Pattern) |
| `lua/beast/libs/lsp/capabilities.lua` | Create | Base caps + contributor registry; returns merged caps |
| `lua/beast/libs/lsp/attach.lua` | Create | Owns `BeastVim-lsp` augroup + `LspAttach` handler dispatch |
| `lua/beast/libs/lsp/keys.lua` | Create | Buffer-local keymap binding from per-server `keys = {...}` via `Key.safe_set` |
| `lua/beast/libs/lsp/diagnostics.lua` | Create | `vim.diagnostic.config(...)` — signs, virtual_text, float, severity sort |
| `lua/beast/libs/lsp/health.lua` | Create | `:checkhealth beast.libs.lsp` |
| `lua/beast/init.lua` | Modify | Wire `packer.lazy("beast.libs.lsp", { event = "FileType", defer = true, setup = ... })` |

## Implementation Phases

### Phase 1: Core lib — Register, capabilities, diagnostics, LspAttach pipeline (MVP)

Smallest viable slice: registering a server with `Beast.lsp.register("lua_ls", { cmd = {...}, filetypes = {"lua"}, ... })` results in an attached LSP client with diagnostics styled and the per-server `on_attach` invoked.

1. **Create `config.lua`** (File: `lua/beast/libs/lsp/config.lua`)
   - Action: Define defaults — `diagnostics = { virtual_text = { source = "if_many", prefix = "●" }, severity_sort = true, float = { border = "rounded", source = "if_many" }, signs = { ... } }`, `inlay_hints = { enabled = false }`, `codelens = { enabled = false }`. Implement `setup(opts)` merging into live `cfg` (deep extend "force"). Export `cfg` directly so peer modules read live values.
   - Why: § *Config Pattern* — all other modules read from `cfg`, never from the `opts` parameter, so runtime mutations propagate.
   - Depends on: None
   - Risk: Low

2. **Create `capabilities.lua`** (File: `lua/beast/libs/lsp/capabilities.lua`)
   - Action:
     - `M.base()` returns `vim.lsp.protocol.make_client_capabilities()`.
     - `M.contributors` table; `M.add(tbl_or_fn)` appends to it.
     - `M.get()` deep-merges `base()` + each contributor (call if function, else use as table).
   - Why: Decouples completion-plugin caps from the lib itself — future blink.cmp wiring calls `Beast.lsp.add_capabilities(require("blink.cmp").get_lsp_capabilities)`.
   - Depends on: None
   - Risk: Low

3. **Create `diagnostics.lua`** (File: `lua/beast/libs/lsp/diagnostics.lua`)
   - Action: `M.setup()` calls `vim.diagnostic.config(cfg.diagnostics)`. Configure sign text via `vim.diagnostic.config({ signs = { text = { [vim.diagnostic.severity.ERROR] = "...", ... } } })`. Read sign chars from `Beast.icon` if available, otherwise sensible defaults.
   - Why: Diagnostics are a global Neovim concern; configure once at `lsp.setup()` time.
   - Depends on: Step 1
   - Risk: Low

4. **Create `attach.lua`** (File: `lua/beast/libs/lsp/attach.lua`)
   - Action:
     - Module-local state: `M.servers = {}` (name → registered cfg), `M.subscribers = {}` (list of `fn(client, bufnr)`).
     - `M.register_server(name, cfg)` — store cfg in `M.servers[name]`.
     - `M.subscribe(fn)` — append to `M.subscribers`.
     - `M.setup()` — create `BeastVim-lsp` augroup (separate from root cache augroup), register single `LspAttach` autocmd. Handler:
       ```
       local client = assert(vim.lsp.get_client_by_id(ev.data.client_id))
       local server = M.servers[client.name]
       if server then
         if server.keys then require("beast.libs.lsp.keys").bind(server.keys, client, ev.buf) end
         if server.on_attach then server.on_attach(client, ev.buf) end
       end
       for _, fn in ipairs(M.subscribers) do fn(client, ev.buf) end
       ```
   - Why: Single autocmd dispatching to per-server + global subscribers — the only `LspAttach` listener the lib creates.
   - Depends on: Step 1
   - Risk: Medium — must not interfere with `Util.root`'s `LspAttach` listener (different augroup ensures isolation).

5. **Create `keys.lua`** (File: `lua/beast/libs/lsp/keys.lua`)
   - Action: `M.bind(keys, client, bufnr)` iterates `keys`; each entry `{lhs, rhs, desc, mode?, group?, cond?}`. If `cond` is a string (LSP method name), check `client:supports_method(cond)` and skip if false. Bind via `Key.safe_set(mode or "n", lhs, rhs, { buffer = bufnr, desc = desc, group = group or "LSP" })`.
   - Why: Per-server keymaps must be buffer-local and cheatsheet-visible. Capability gating prevents binding `gd` when the server lacks `textDocument/definition`.
   - Depends on: Step 4
   - Risk: Low

6. **Create `init.lua`** (File: `lua/beast/libs/lsp/init.lua`)
   - Action: Public API surface:
     - `M.setup(opts)` — calls `config.setup(opts)` → `diagnostics.setup()` → `attach.setup()`. Idempotent (guard with `M._initialized`).
     - `M.register(name, cfg)` — split BeastVim-specific fields (`keys`, `on_attach`) from `vim.lsp.Config` fields. If `cfg.capabilities` not provided, default to `capabilities.get()`. Call `vim.lsp.config(name, lsp_cfg)` then `vim.lsp.enable(name)`. Pass full original `cfg` (including `keys`/`on_attach`) to `attach.register_server(name, cfg)`.
     - `M.capabilities()` → `capabilities.get()`.
     - `M.add_capabilities(x)` → `capabilities.add(x)`.
     - `M.on_attach(fn)` → `attach.subscribe(fn)`.
   - Why: Single entry point matching § *File Structure* convention.
   - Depends on: Steps 1–5
   - Risk: Low

7. **Wire into `beast/init.lua`** (File: `lua/beast/init.lua`)
   - Action: Add `packer.lazy("beast.libs.lsp", { event = { name = "FileType", defer = false }, setup = function(lsp) lsp.setup(cfg.lsp or {}) end })`. **No `defer`** — must be loaded before `FileType` autocmds fire so first-buffer LSPs attach. Add `lsp?: Beast.LSP.Config` to `Beast.Config` typedef.
   - Why: Lazy on FileType means no LSP cost when opening explorer-only / startup scratch sessions; eager once a real filetype is detected.
   - Depends on: Step 6
   - Risk: Medium — `FileType` fires before `BufReadPost`; verify register happens early enough. If a regression, fall back to `event = "VeryLazy"` style (`User VimEnter` deferred).

8. **Manual verification** (no test infra yet — see § *Testing Strategy*)
   - Action: In `beast/init.lua` add a temporary call after the lazy registration:
     ```lua
     Beast.lsp.register("lua_ls", {
       cmd = { "lua-language-server" },
       filetypes = { "lua" },
       root_markers = { ".luarc.json", ".git" },
     })
     ```
   - Open a `.lua` file → confirm `:lua =vim.lsp.get_clients()` shows `lua_ls` attached, diagnostics render with configured signs/virtual_text. Remove the temporary call before commit.
   - Depends on: Step 7
   - Risk: Low

### Phase 2: Health check + commands surface

Smallest follow-up: discoverability via `:checkhealth` and one ergonomic command for debugging.

1. **Create `health.lua`** (File: `lua/beast/libs/lsp/health.lua`)
   - Action: Use `vim.health.start` / `ok` / `warn` / `error`. Report:
     - Neovim version (≥ 0.11 required, ≥ 0.12 recommended for `vim.lsp.enable`).
     - Registered server names (from `attach.servers`).
     - For each registered server: enabled? Has `cmd[1]` executable on `$PATH`?
     - Attached clients for current buffer (`vim.lsp.get_clients({ bufnr = 0 })`).
     - Capability contributor count.
   - Why: Matches the discoverability surface of `beast/libs/treesitter/health.lua`.
   - Depends on: Phase 1
   - Risk: Low

2. **Add `:BeastLspInfo` command** (File: `lua/beast/libs/lsp/init.lua`)
   - Action: In `M.setup`, register `vim.api.nvim_create_user_command("BeastLspInfo", function() ... end, {})`. Opens a `Util.scratch_buf` (per existing util) with: registered servers list, attached clients per buffer, current capabilities. **Do not** duplicate `:checkhealth` — this is a focused per-buffer view.
   - Why: Faster than `:checkhealth` for the common debug case ("why isn't this server attached?").
   - Depends on: Step 1
   - Risk: Low

## Testing Strategy

- **Unit tests**: `tests/` is currently sparse. Add `tests/lsp_spec.lua` (busted-style if a runner exists; otherwise a `nvim --headless -l` script). Cover:
  - `register("foo", { cmd = {"true"} })` → `vim.lsp.config._configs.foo` populated; `vim.lsp.enable` called.
  - `add_capabilities` → `capabilities()` reflects the contribution.
  - Per-server `keys` with `cond = "textDocument/definition"` → not bound when method unsupported.
  - The `LspAttach` handler invokes per-server `on_attach` exactly once per `(client, buffer)` pair.
- **Bench**: No hot-path concern in this lib (`LspAttach` fires once per attach, not per redraw). **No bench script required.** If diagnostic rendering shows up in `bench-statuscolumn.lua`, that's a statuscolumn concern, not this lib's.
- **Manual verification (mandatory, Phase 1)**:
  1. `nvim --clean -u init.lua some-file.lua` (after temporary register call in Step 1.8).
  2. `:lua =vim.lsp.get_clients()` — `lua_ls` present with merged capabilities.
  3. Force a syntax error → diagnostic appears with configured sign + virtual_text style.
  4. `:checkhealth beast.libs.lsp` (Phase 2) — all sections green.
  5. `:lsp stop` then `:lsp restart` — confirm reattach.
  6. Open `~/scratch/foo.lua` outside any project → server still attaches (no `root_markers` match falls back to single-file mode).

## Risks & Mitigations

- **Risk**: `LspAttach` autocmd ordering. Per-server `on_attach` should run **before** subscribers so subscribers see fully-initialized state.
  → **Mitigation**: Single autocmd, hard-coded order (per-server first, then subscribers in registration order). Documented in `attach.lua` module header.

- **Risk**: `vim.lsp.enable(name)` calls accumulate across re-`setup()`. If user calls `lsp.setup()` twice, servers registered between calls might leak.
  → **Mitigation**: `setup` is idempotent (guard via `M._initialized`). `register` is deduplicated by name (last write wins on `attach.servers[name]`); `vim.lsp.config` already supports re-registration.

- **Risk**: Conflict with `Util.root`'s `LspAttach` listener (same event, different responsibility).
  → **Mitigation**: Separate `augroup`: `BeastVim-lsp` (this lib) vs `BeastVim-root_cache` (`util/root.lua:367`). Both run independently.

- **Risk**: Neovim 0.12 default global keymaps (`K`, `gd`, `grr`, ...) may surprise users coming from older configs.
  → **Mitigation**: Document in lib header comment; do not override. Per-server `keys` are for *extensions* (gD, gR, <leader>co, etc.) that augment defaults.

- **Risk**: `vim.lsp.protocol.make_client_capabilities()` already includes most modern caps; over-extending via contributors may produce duplicate fields that confuse servers.
  → **Mitigation**: Use `vim.tbl_deep_extend("force", ...)` — same semantics as core. Test with `add_capabilities` returning an empty table (no-op).

- **Risk**: Single-file mode (no `root_markers` match) — some servers (eslint with `workspace_required = true`) refuse to attach.
  → **Mitigation**: That's *server-specific* config, owned by the future lang extension. The lib does the right thing by passing `workspace_required` through to `vim.lsp.config`.

- **Risk**: Lazy-load timing — if `lsp` lib loads on `FileType` but the very first filetype event happens before `packer.lazy` resolves it, the server won't attach for that buffer.
  → **Mitigation**: Load `defer = false` (eager on first `FileType`). If still racy, switch to `VimEnter` + manual `vim.lsp.start` for already-open buffers (mirrors `treesitter` lib pattern).

## Success Criteria

- [ ] `Beast.lsp.register("lua_ls", { cmd, filetypes, root_markers })` attaches a working LSP client on `.lua` files with diagnostics rendered per configured style.
- [ ] `:checkhealth beast.libs.lsp` returns green with one registered server and one attached client.
- [ ] `Beast.lsp.add_capabilities({ textDocument = { foo = true } })` followed by `Beast.lsp.capabilities()` shows the merged contribution.
- [ ] Per-server `keys = { { "gD", fn, cond = "textDocument/definition" } }` binds buffer-locally only when the server supports the method.
- [ ] No regression in `Util.root` — `:lua =require("beast.util.root").get()` still resolves correctly after LSP attach (validates augroup isolation).
- [ ] `bench-startup.sh` shows no startup regression vs `main` (lib is lazy-loaded on `FileType`).
- [ ] Codemap regenerated (`docs/CODEMAPS/libraries.md` includes new `lsp` section) and committed.

## ADR Required

This dev spec involves architectural decisions that must be documented as ADRs once committed:

- **Decision: BeastVim-native LSP infrastructure layer over native `vim.lsp.config` + `vim.lsp.enable`, with no dependency on `nvim-lspconfig` or `mason-lspconfig`.** Supersedes the legacy `~/.config/nvim/lua/beastvim/plugins/lang/*` pattern (lazy.nvim opts-merging on `mason.nvim`).
- **Decision: Server registry ownership boundary** — the `lsp` lib owns no per-server knowledge. Server configs live in future `BeastVim/<Lang>` extension repos installed via `vim.pack`. This is a deliberate split (mirrors the treesitter lib's "we own setup, not parser lists" stance).
- **Decision: `register(name, cfg)` API shape** — accepts a `vim.lsp.Config` augmented with `keys` and `on_attach` BeastVim extensions. This becomes the public contract for all future lang extensions, so freeze it intentionally in an ADR before downstream consumers depend on it.
