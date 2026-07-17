# Dev Spec: LSP Infra Hardening

> **Status:** ✅ Completed 2026-06-09 (all 5 phases shipped — commits `656c7b3`, `f828859`, `a52b4ac`, plus Phase 4 bench/test scaffolding and Phase 5 docs).
>
> **Postscript 2026-06-09:** Phase 1's "deferred capabilities resolution via function thunk" approach was **incorrect** — Neovim 0.12's `vim.lsp` validator strictly requires `capabilities` to be a `table` (`runtime/lua/vim/lsp/client.lua:331`: `validate('capabilities', config.capabilities, 'table', true)`). The thunk caused `capabilities: expected table, got function` at server start. Fixed by stamping a snapshot table at `register()` time **and** installing a chained `before_init` hook that re-resolves `M.capabilities()` at the moment the `initialize` request is sent. Net behaviour matches the original spec intent (late contributors reach not-yet-started servers); a new test asserts `vim.validate("capabilities", stored.capabilities, "table", true)` so this class of regression is caught by `tests/test-lsp.lua` going forward.

## Summary

Harden `beast.libs.lsp` so it manages the lifecycle smartly enough to absorb the per-server diversity that `BeastVim/<Lang>` extensions will produce. Five infra-level changes — deferred capabilities resolution, inlay-hints + codelens lifecycle, per-server preflight (`enabled` + executable check), idempotent re-/un-registration, and a documented capability-contributor ordering rule. Per-server data still lives in external extension repos (ADR-030); this spec only changes the infra contract those repos depend on.

## Requirements

- **Capabilities are evaluated at client-start time, not at `register()` time.** A server registered before `Lsp.add_capabilities(blink_caps)` runs must still start with blink's caps included.
- **`config.inlay_hints.enabled = true` actually enables inlay hints.** Today the field exists but no code reads it. The `LspAttach` dispatcher must turn it on (capability-gated) per buffer.
- **`config.codelens.enabled = true` actually enables codelens.** Same gap — wire `vim.lsp.codelens.refresh()` on `BufEnter` / `CursorHold` (capability-gated) per buffer.
- **`Lsp.register(name, cfg)` accepts an optional `enabled` field** (`fun(): boolean`). If it returns `false`, the lib silently skips `vim.lsp.config` / `vim.lsp.enable` for that server. Extensions use this to guard on executables, project markers, etc.
- **`Lsp.register` is idempotent.** Calling it twice with the same name replaces the previous spec (does not double-register `extras` in the dispatcher). Lets extensions hot-swap their cfg without `:source`-ing twice causing duplicate `on_attach` calls.
- **`Lsp.unregister(name)`** removes the dispatcher `extras` entry and calls `vim.lsp.enable(name, false)`. Needed for per-project disable and for `:LspRestart`-style flows.
- **A documented "capabilities contributors register early" convention.** The dispatcher cannot enforce ordering across plugin lazy-loads, but it can detect mis-ordering and surface it via `:checkhealth`.

## Out of Scope

- In-repo per-server data (`lua/beast/lsp/servers/*`). ADR-030 keeps that in external `BeastVim/<Lang>` repos. This spec does not supersede ADR-030.
- A `beast.lsp.extensions` coordinator that auto-loads extensions on `FileType`. Separate spec when at least one extension exists to test against.
- Binary install / mason integration. ADR-030 alt #5; out of scope.
- Restart-already-attached-clients when caps change. Documented as a known limitation; not auto-restarted.
- New keymap shape changes (ADR-031 contract is frozen). `keys`, `cond`, `on_attach`, `Key.safe_set` semantics unchanged.
- Renaming `Lsp.*` public API. All additions are new methods; no breaking renames.

## Research

### Repo Search

- Searched for: `inlay_hint`, `codelens`, `supports_method`, `capabilities`, `vim.lsp.config`, `vim.lsp.enable`, `Lsp.register`, `Lsp.add_capabilities`.
- Found:
  - `lua/beast/libs/lsp/config.lua:49-54` — `inlay_hints = { enabled = false }` and `codelens = { enabled = false }` declared but **no consumer reads them**. `grep` confirms zero references outside `config.lua` itself.
  - `lua/beast/libs/lsp/init.lua:104-106` — capabilities snapshot is eager (`lsp_cfg.capabilities = M.capabilities()`). This is the bug identified in chat review and called out as a known limitation in ADR-031 § *Consequences*.
  - `lua/beast/libs/lsp/attach.lua:36-38` — `M.register_server(name, extras)` overwrites `M.servers[name]` (already idempotent for the *extras* table). But `init.lua:108-111` always calls `vim.lsp.config(name, lsp_cfg)` + `vim.lsp.enable(name)`; no guard against the *server-spec* being silently re-stamped.
  - `lua/beast/libs/lsp/attach.lua:52-66` — `apply_fold(client, buf)` is the existing precedent for "if config.<feature>.enabled and client supports it, mutate the buffer." Inlay/codelens follow the same shape.
  - `lua/beast/libs/lsp/health.lua:62-64` — `Capability contributors: N` is reported but there's no check that contributors registered before any client attached. Cheap signal to add.
  - `lua/beast/libs/lsp/keys.lua:25-34` — `client:supports_method(cond)` is already used for keymap gating; same primitive applies to inlay/codelens.
  - **No callers exist yet** for `Lsp.register` / `Lsp.add_capabilities` outside the lib (`grep -rn "Lsp.register\|Lsp.add_capabilities" lua/` returns nothing). Means the cap-thunk change is breaking-free.
  - `lua/beast/libs/lsp/init.lua:23` — `BEAST_FIELDS = { keys = true, on_attach = true }`. Need to extend with `enabled = true` so it's stripped before `vim.lsp.config` passthrough (otherwise nvim would log "unknown field").
- Reuse opportunity:
  - **Adopt** the `apply_fold` shape (`attach.lua:52-66`) for `apply_inlay_hints` and `apply_codelens`. Same `if cfg.X.enabled and supports_method(...)` guard, same dispatcher entry point.
  - **Adopt** `client:supports_method(...)` (`keys.lua:27`) — proven primitive.
  - **Adopt** `vim.lsp.config(name, false)` (Neovim 0.12 nil-out idiom) for unregister.
  - **Adopt** `health.warn` (`health.lua:25`) for the contributor-after-attach detection.

### Package Search

- Searched: Neovim 0.12 API for `vim.lsp.Config.capabilities` thunk support, `vim.lsp.inlay_hint`, `vim.lsp.codelens`, `vim.lsp.config(name, false)` un-set semantics.
- Found:
  - `:h vim.lsp.Config` — `capabilities` accepts `lsp.ClientCapabilities|fun(): lsp.ClientCapabilities`. **The function form is resolved at `vim.lsp.start_client()` time**, which happens inside the `vim.lsp.enable`-installed FileType autocmd. This is exactly the deferral we need.
  - `:h vim.lsp.inlay_hint.enable(true, { bufnr })` — buffer-scoped toggle, returns silently if unsupported. No need to manage extmarks ourselves.
  - `:h vim.lsp.codelens.refresh({ bufnr })` + `vim.lsp.codelens.on_codelens()` — refresh is the trigger; display is automatic when codelens results arrive.
  - `vim.lsp.config(name, nil)` (or assigning `vim.lsp.config[name] = nil`) clears a previously-set config. Combined with `vim.lsp.enable(name, false)` (0.12+), this fully un-enables.
- Decision: **Use native** — every primitive exists in core. No new plugin, no vendored code. Consistent with ADR-029 (native LSP infra, no nvim-lspconfig).

## Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/libs/lsp/init.lua` | Modify | Capabilities thunk; add `enabled` field to `BEAST_FIELDS`; honor `cfg.enabled`; idempotent re-register; add `M.unregister(name)`. |
| `lua/beast/libs/lsp/attach.lua` | Modify | Add `apply_inlay_hints` and `apply_codelens` helpers; call them in the LspAttach callback after `apply_fold`. Track first-attach timestamp for the health check. |
| `lua/beast/libs/lsp/capabilities.lua` | Modify | Track `M.first_attach_seen` flag; warn on `add()` if a client has already attached. |
| `lua/beast/libs/lsp/config.lua` | Modify | Document `inlay_hints.enabled` / `codelens.enabled` are now wired; bump `@class Beast.LSP.Codelens` with `events?: string[]` for refresh trigger override. |
| `lua/beast/libs/lsp/health.lua` | Modify | Add "Capability contributors registered after first attach (will not affect those clients)" warning when applicable. List inlay-hint / codelens enabled status. |
| `scripts/bench-lsp.lua` | Create | Bench `Lsp.capabilities()` resolution (called per client start) — must stay under threshold even with N contributors. |
| `tests/test-lsp.lua` | Create | Manual repro: `nvim --clean -u tests/test-lsp.lua` opens a buffer with a fake server registered, demonstrates inlay/codelens/cap-thunk behavior. |
| `docs/CODEMAP/libraries.md` | Modify | Update `lsp` entry: new `Lsp.unregister`, `enabled` field, inlay/codelens wiring, capabilities-thunk note. |

## Implementation Phases

### Phase 1: Capabilities thunk + `enabled` field — fix the eager-snapshot bug, add preflight

The minimum slice. Self-contained, no ordering coupling with other phases. After this phase, blink-cmp + lsp interactions are correct.

1. **Add `enabled` to `BEAST_FIELDS` allowlist** (File: `lua/beast/libs/lsp/init.lua:23`)
   - Action: `local BEAST_FIELDS = { keys = true, on_attach = true, enabled = true }`
   - Why: `enabled` is a BeastVim extension field, must be stripped before `vim.lsp.config` passthrough.
   - Depends on: None
   - Risk: Low

2. **Honor `cfg.enabled` in `M.register`** (File: `lua/beast/libs/lsp/init.lua:101-112`)
   - Action: Inside `register(name, cfg)`, after `split_spec` but before `vim.lsp.config(...)`:
     ```lua
     if extras.enabled and extras.enabled() == false then
       require("beast.libs.lsp.attach").register_server(name, extras)  -- still record for health
       return  -- do not call vim.lsp.config / vim.lsp.enable
     end
     ```
   - Why: Lets extensions guard on missing binaries (`return vim.fn.executable("lua-language-server") == 1`) without writing a wrapper.
   - Depends on: Step 1
   - Risk: Low

3. **Replace eager capabilities snapshot with a thunk** (File: `lua/beast/libs/lsp/init.lua:104-106`)
   - Action: Change
     ```lua
     if lsp_cfg.capabilities == nil then
       lsp_cfg.capabilities = M.capabilities()
     end
     ```
     to
     ```lua
     if lsp_cfg.capabilities == nil then
       lsp_cfg.capabilities = function() return M.capabilities() end
     end
     ```
   - Why: Defers contributor merging to `vim.lsp.start_client()` time. Eliminates the snapshot-at-register bug documented in ADR-031 § *Consequences*.
   - Depends on: None
   - Risk: Low — `vim.lsp.Config.capabilities` accepts a function in 0.11+; the dev spec's Neovim baseline is 0.12 (per ADR-029).

4. **Idempotent re-register** (File: `lua/beast/libs/lsp/init.lua` `M.register`)
   - Action: Call `vim.lsp.config(name, nil)` before re-stamping when `attach.servers[name]` is already present, to clear the prior merged cfg (avoids unbounded deep-merge accumulation across re-registers).
   - Why: `vim.lsp.config(name, cfg)` is documented to deep-merge over the existing entry, so calling it 3× with `{ settings = { Lua = { ... } } }` accumulates. Clearing first means re-register replaces, not stacks.
   - Depends on: None
   - Risk: Low

5. **Add `M.unregister(name)`** (File: `lua/beast/libs/lsp/init.lua`, new method)
   - Action:
     ```lua
     function M.unregister(name)
       vim.lsp.enable(name, false)
       vim.lsp.config(name, nil)
       require("beast.libs.lsp.attach").servers[name] = nil
     end
     ```
   - Why: Enables per-project disable patterns and clean `:LspRestart`-style flows. Already-attached clients keep running; new `FileType` events won't start the server until re-registered.
   - Depends on: None
   - Risk: Low

### Phase 2: Inlay hints + codelens lifecycle — wire the config fields that already exist

Independent of Phase 1; could land first or after. Self-contained in `attach.lua`.

1. **Add `apply_inlay_hints(client, buf)`** (File: `lua/beast/libs/lsp/attach.lua`)
   - Action: Mirror `apply_fold`:
     ```lua
     local function apply_inlay_hints(client, buf)
       local cfg = require("beast.libs.lsp.config")
       if not (cfg.inlay_hints and cfg.inlay_hints.enabled) then return end
       if not client:supports_method("textDocument/inlayHint") then return end
       vim.lsp.inlay_hint.enable(true, { bufnr = buf })
     end
     ```
   - Why: `config.inlay_hints.enabled = true` becomes a real switch instead of dead config.
   - Depends on: None
   - Risk: Low

2. **Add `apply_codelens(client, buf)`** (File: `lua/beast/libs/lsp/attach.lua`)
   - Action:
     ```lua
     local function apply_codelens(client, buf)
       local cfg = require("beast.libs.lsp.config")
       if not (cfg.codelens and cfg.codelens.enabled) then return end
       if not client:supports_method("textDocument/codeLens") then return end
       local events = cfg.codelens.events or { "BufEnter", "CursorHold", "InsertLeave" }
       vim.api.nvim_create_autocmd(events, {
         group = augroup,                              -- existing BeastVim-lsp augroup
         buffer = buf,
         callback = function() vim.lsp.codelens.refresh({ bufnr = buf }) end,
       })
       vim.lsp.codelens.refresh({ bufnr = buf })       -- initial paint
     end
     ```
   - Why: Same shape as inlay hints; codelens needs an explicit refresh trigger (unlike inlay hints which are pulled by core).
   - Depends on: None
   - Risk: Medium — autocmds keyed to `buffer = buf` are auto-cleared on buffer wipe (Neovim guarantee), no leak. But re-attach on same buffer would duplicate the autocmd; guard with a `vim.b[buf].beast_lsp_codelens_armed` flag.

3. **Extend `Beast.LSP.Codelens` type** (File: `lua/beast/libs/lsp/config.lua`)
   - Action: Add `---@field events? string[]` to the class annotation and the same key to `defaults.codelens`.
   - Why: Lets users override refresh events without forking the lib.
   - Depends on: Step 2
   - Risk: Low

4. **Call both helpers from the dispatcher** (File: `lua/beast/libs/lsp/attach.lua` LspAttach callback)
   - Action: After `apply_fold(client, ev.buf)` add:
     ```lua
     apply_inlay_hints(client, ev.buf)
     apply_codelens(client, ev.buf)
     ```
   - Why: Hook them into the same per-attach path as fold.
   - Depends on: Steps 1, 2
   - Risk: Low

### Phase 3: Capability-contributor ordering guard — surface the foot-gun, don't enforce it

Pure observability. No behavior change unless contributors are added after attach.

1. **Track first attach** (File: `lua/beast/libs/lsp/capabilities.lua`)
   - Action: Add `M.first_attach_seen = false`. From `attach.lua`'s LspAttach callback, set `require("beast.libs.lsp.capabilities").first_attach_seen = true` on the first run.
   - Why: The signal needed for the health-check warning and the runtime warning.
   - Depends on: None
   - Risk: Low

2. **Warn on late `add`** (File: `lua/beast/libs/lsp/capabilities.lua` `M.add`)
   - Action: If `M.first_attach_seen` is true at `add()` time, `vim.notify("beast.libs.lsp: capabilities contributor added after a client attached; existing clients won't see it", vim.log.levels.WARN)`.
   - Why: Catches the blink.cmp-loaded-too-late case at the moment it happens, not at `:checkhealth` time.
   - Depends on: Step 1
   - Risk: Low

3. **Health check row** (File: `lua/beast/libs/lsp/health.lua`)
   - Action: After the "Capability contributors: N" info line, if `caps.first_attach_seen and #caps.contributors > 0`, add a tip line: "Tip: contributors should be added before any LspAttach (typically in `beast/init.lua`)".
   - Why: Static documentation surface for the convention.
   - Depends on: Step 1
   - Risk: Low

4. **Health check rows for inlay/codelens** (File: `lua/beast/libs/lsp/health.lua`)
   - Action: `health.info(string.format("inlay_hints.enabled: %s", tostring(cfg.inlay_hints.enabled)))`, same for `codelens`.
   - Why: Self-documenting state for `:checkhealth` users.
   - Depends on: Phase 2
   - Risk: Low

### Phase 4: Bench + test scaffolding — measure capability resolution cost

Currently no bench/test for the lsp lib (conventions § 8 expects one). This phase fills the gap.

1. **`scripts/bench-lsp.lua`** (File: `scripts/bench-lsp.lua`, new)
   - Action: Register 50 capability contributors (mix of tables and functions), run `Lsp.capabilities()` 1000× and report median µs. Threshold: < 50 µs per call (cheap enough for per-client-start use).
   - Why: The thunk change moves capability merging from once-per-`register` to once-per-`vim.lsp.start_client`. Need to confirm the merge stays cheap.
   - Why this threshold: Each LSP start already runs many ms of work (binary spawn, init handshake); adding < 50 µs is invisible. Choose the bench number conservatively.
   - Depends on: Phase 1 step 3
   - Risk: Low

2. **`tests/test-lsp.lua`** (File: `tests/test-lsp.lua`, new)
   - Action: `nvim --clean -u tests/test-lsp.lua` setup that registers a no-op server with stubbed cmd, adds a capability contributor *after* registration, opens a scratch buffer, asserts the stubbed server's start would have received the late contributor's caps (by inspecting the resolved thunk).
   - Why: Manual repro for the original bug; serves as regression coverage.
   - Depends on: Phase 1 step 3
   - Risk: Low

### Phase 5: Documentation — update codemap + ADR notes

1. **Update codemap** (File: `docs/CODEMAP/libraries.md`)
   - Action: In the `lsp` section, add `Lsp.unregister`, the `enabled` field, the capabilities-thunk note, and the inlay/codelens wiring. Update the file-tree comment for `init.lua` API list.
   - Why: Codemap-freshness instruction (`docs/CODEMAP/**` instructions file) requires updates when public API changes.
   - Depends on: Phases 1, 2
   - Risk: Low

2. **ADR-031 footnote** (File: `docs/ADRs/031-lsp-register-api-keys-on-attach-extensions.md`)
   - Action: Add a single line under § *Consequences* — "Update 2026-MM-DD: capabilities are now resolved via thunk at client-start time; the snapshot limitation noted above no longer applies. See dev-spec `lsp-infra-hardening.md`."
   - Why: ADR-031 explicitly documented the snapshot bug as a known limitation; closing that loop avoids future readers thinking it's still an issue.
   - Depends on: Phase 1 step 3 merged
   - Risk: Low

## Testing Strategy

- **Bench** (`scripts/bench-lsp.lua`): `Lsp.capabilities()` median < 50 µs with 50 contributors. Final line `BENCH name=lsp ... status=PASS|FAIL` (per conventions § 8).
- **Manual test** (`tests/test-lsp.lua`): runnable via `nvim --clean -u tests/test-lsp.lua`; demonstrates (a) capability added after register reaches the next client start, (b) inlay hints toggle on/off when `cfg.inlay_hints.enabled` flips, (c) `Lsp.unregister(name)` prevents subsequent `FileType` starts.
- **Health**: `:checkhealth beast.libs.lsp` clean in default config; warns specifically when contributors are added after first attach (forced repro: add a contributor inside a `LspAttach` autocmd in the test file).
- **No unit-test framework added.** Conventions § 8 specifies bench + manual repro; matches existing libs (`tests/test-explorer.lua`, `tests/test-finder.lua`, etc.).

## Risks & Mitigations

- **Risk:** `capabilities` as a function isn't honored by `vim.lsp.start_client` on the target Neovim build → **Mitigation:** ADR-029 already pins the baseline at Neovim 0.12; `:h vim.lsp.Config` for 0.12 explicitly lists the function form. Health check (Phase 3) will surface the failure mode (warning + observable empty caps) immediately.
- **Risk:** Codelens autocmd duplicated on re-attach to the same buffer → **Mitigation:** `vim.b[buf].beast_lsp_codelens_armed` flag (Phase 2 step 2 note); short-circuit if set.
- **Risk:** `vim.lsp.config(name, nil)` clearing behavior differs across patch versions → **Mitigation:** Fall back to direct table assignment (`vim.lsp.config[name] = nil`) if `nil`-passing is rejected by `vim.validate`. Cover in test-lsp.lua.
- **Risk:** Bench threshold is too tight in CI environments → **Mitigation:** Use median (not max) over 1000 runs, ignore first 10 runs as warm-up. If still flaky, relax to < 100 µs with rationale recorded.
- **Risk:** `enabled = function()` runs at every `register()` call, including potentially expensive checks (file I/O) at startup → **Mitigation:** Document that `enabled` should be cheap (executable check, env-var test). Extensions needing async checks can defer the `Lsp.register` call instead of doing it inside `enabled`.

## Success Criteria

- [ ] `Lsp.capabilities()` is called once per client start, not once per `register()` (verified by test-lsp.lua hook).
- [ ] `:checkhealth beast.libs.lsp` reports inlay-hints and codelens enabled status, plus a warning when contributors registered after first attach.
- [ ] `scripts/bench-lsp.lua` reports `status=PASS` with median < 50 µs.
- [ ] `tests/test-lsp.lua` passes the three manual scenarios listed in Testing Strategy.
- [ ] `Lsp.register` is idempotent — calling twice with the same name leaves `attach.servers[name]` with the second cfg only (no accumulation).
- [ ] `Lsp.unregister(name)` followed by opening a matching `FileType` does NOT start the server.
- [ ] `docs/CODEMAP/libraries.md` regenerated and committed; codemap-freshness header date matches the commit day.
- [ ] `stylua --check lua/beast/libs/lsp/` clean.
- [ ] ADR-031 footnote added; no other ADR changes needed (the additions are mechanism-level, not architectural).

## ADR Required

This dev spec does **not** introduce new architectural decisions — every change is a refinement of contracts already accepted in ADR-029 (native LSP infra), ADR-030 (extension ownership of per-server data), and ADR-031 (`Lsp.register` shape). The capabilities-thunk change closes a known limitation documented in ADR-031 § *Consequences*; that ADR gets a footnote (Phase 5 step 2), not a new ADR.

If during implementation we decide to do **any** of the following, an ADR becomes required:
- Add per-server data files inside this repo (would supersede ADR-030).
- Add an in-repo `beast.lsp.extensions` coordinator (new module = new architectural surface).
- Change the `BEAST_FIELDS` allowlist beyond adding `enabled` (would supersede ADR-031's "small, stable allowlist" rationale).
