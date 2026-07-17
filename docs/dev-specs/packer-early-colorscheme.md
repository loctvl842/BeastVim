---
name: packer-early-colorscheme
description: "Packer Early Colorscheme"
generated: 2026-05-04
---

# Dev Spec: Packer Early Colorscheme

## Summary
Add a `colorscheme` config field to `beast.libs.packer.config` that — when set
and when the named plugin is already installed on disk — eagerly loads the
colorscheme plugin and applies its colorscheme **at the very start of
`packer.setup()`**, before any other plugin work. This eliminates the visible
"default colorscheme flash" that happens between Neovim startup and the moment
the colorscheme plugin's normal lazy/eager trigger fires. If the plugin is not
installed (first run) or the field is `nil`, the early-apply step is a no-op
and the colorscheme is loaded normally later by the existing setup pipeline.

## Requirements (from user request)

- Support `config.colorscheme = { name = '<colorscheme>', plugin = '<plugin-dir-name>' }`.
- During `packer.setup()`:
  - If `colorscheme` is `nil` → skip silently.
  - If specified but plugin **is not installed** → skip silently (it will load via its normal trigger after `vim.pack.add` installs it).
  - If specified and plugin **is installed** → eagerly `packadd` it, run its `config()`, and apply `:colorscheme <name>` *before* the rest of `setup()` runs.
- Eager load must include the spec's `config()` (full eager load, not packadd-only).
- Must not double-load the plugin if it is also classified as `eager` or has a lazy trigger.
- Must not break the case where `colorscheme` is `nil` (current behaviour).

## Out of scope

- String shortcut form (`colorscheme = "monokai-pro.nvim"`). Decided: table form only.
- Auto-deriving `name` from `plugin` (e.g. stripping `.nvim`).
- Validating that the colorscheme `name` actually corresponds to the plugin.
- Falling back to a different colorscheme on failure.

## Research

### Repo Search
- Searched for: `colorscheme` in `lua/`, `packer.config`, `state.installed_plugins`, `state.load`, `vim.pack.add`, `vim.pack.get`.
- Found:
  - `lua/beast/libs/packer/config.lua:10` already declares `colorscheme = nil` in `defaults` but nothing reads it. The field exists as a stub — this dev spec wires it up.
  - `lua/beast/libs/packer/state.lua:33` has `installed_plugins` table populated via `vim.pack.get()` inside `vim.schedule(...)` in `init.lua`. Because it is deferred, it cannot be relied on synchronously at the top of `setup()`.
  - `lua/beast/libs/packer/state.lua:72` has `M.load(name, reason)` — handles dependencies, `packadd`, runs `spec.config()`, profile, and operation tracking. Reuse this for the eager load.
  - `lua/beast/libs/packer/init.lua:128` is `packer.setup(specs)` — the entry point we extend.
  - `lua/beast/init.lua:74` is the only caller: `packer.setup(cfg.packer)`.
  - `lua/beast/plugins/colorscheme.lua` shows current colorscheme plugins. `monokai-pro.nvim` uses `lazy = { event = "UIEnter" }` (the exact case where the flash is visible). `rose-pine` uses `lazy = false` and calls `vim.cmd.colorscheme("rose-pine")` in its config.
- Reuse opportunity: **Yes** — reuse `state.load()` for the eager load (handles deps + config + profile). Reuse the existing `defaults.colorscheme = nil` field and the `config.setup(opts)` deep-merge pattern.

### Package Search
- Lua/Neovim ecosystem: this is a startup-flicker mitigation specific to BeastVim's custom `packer` lib. There is no shared package.
- Decision: **Build** — a small helper inside `packer/init.lua` (≤ 30 lines). No new files needed; this is a single integration point.

## Architecture Changes

- **Modified: `lua/beast/libs/packer/init.lua`**
  - Add a private helper `apply_early_colorscheme()` called once inside `M.setup(specs)`, **after** the existing init-loop and the existing classification loop (so `init()` already ran for every spec, all specs are registered in `state.plugins`, and `eager_specs` is fully populated), but **before** `vim.pack.add`.
  - The helper:
    1. Reads `config.colorscheme`. If `nil`, returns `nil` immediately.
    2. Validates the table shape (`name` and `plugin` are non-empty strings); on bad shape, `vim.notify` a warning and return `nil`.
    3. Checks `vim.uv.fs_stat(vim.fn.stdpath("data") .. "/site/pack/core/opt/" .. plugin)` for installation. (Synchronous, side-effect-free, fast.)
    4. Looks up the plugin's spec from `state.plugins[plugin]`. If not found (filtered by `cond`, `enabled`, etc.), returns `nil` silently.
    5. Verifies that **every** dependency in `spec.dependencies` is also installed on disk via the same `fs_stat` check. If any dep is missing, returns `nil` silently — fall back to the normal install/load path.
    6. Calls `state.load(plugin, { type = "eager", detail = "colorscheme" })` wrapped in `pcall`. This handles deps + `packadd` + `spec.config()` + profile + operation tracking.
    7. **Rollback on failure**: if `state.load` errored, manually clear `state.loaded_plugins[plugin]` (and for any deps it tried to load) so the normal trigger path can retry. This works around the pre-existing bug in `state.load` where `loaded_plugins[name] = true` is set *before* `vim.cmd.packadd`, leaving the flag stuck on failure.
    8. On success, returns the `plugin` name. Fires `pcall(vim.cmd.colorscheme, name)` as a final safety net (most colorscheme `config()` already call it; some — e.g. `tokyonight` — only define the scheme without applying it).
  - **Skip duplicate eager `config()`**: in the existing "Step 5: Load eager plugins and run their config" loop, add a guard: skip the spec if `state.loaded_plugins[spec.name]` is already `true`. Without this, `lazy = false` colorschemes (rose-pine, tokyonight, catppuccin) would have their `config()` run twice — once from `state.load` in the helper, once from the eager loop.
  - **No change needed to `vim.pack.add`'s `load` callback**: it already calls `state.load`, which short-circuits on `loaded_plugins[name]`.
  - **Lazy trigger registration is left intact** for the early-loaded plugin: triggers (`event`, `cmd`, `keys`, etc.) all funnel through `state.load`, which short-circuits. This is harmless and avoids special-casing.

- **Modified: `lua/beast/libs/packer/config.lua`**
  - Add `---@class Beast.Packer.Colorscheme` annotation above `defaults`:
    ```lua
    ---@class Beast.Packer.Colorscheme
    ---@field name string         -- :colorscheme <name>
    ---@field plugin string       -- plugin directory name (matches spec.name)
    ```
  - Update `Beast.Packer.Config`'s annotation to include `colorscheme?: Beast.Packer.Colorscheme`.
  - No runtime change in this file — the field already exists in `defaults` as `nil`.

- **Modified: `lua/beast/init.lua`**
  - Before `packer.setup(cfg.packer)`, call `require("beast.libs.packer.config").setup({ colorscheme = ... })` so the user can configure it via `Beast.Config`. Add a `packer_config` (or similar) field to `Beast.Config.defaults`:
    ```lua
    packer_config = {
        colorscheme = nil, -- { name = "monokai-pro", plugin = "monokai-pro.nvim" }
    },
    ```
    Then in `M.setup(opts)`:
    ```lua
    require("beast.libs.packer.config").setup(cfg.packer_config or {})
    ```
  - Also extend `Beast.Config` annotation with `packer_config?: Beast.Packer.Config`.

- **No new files** — the helper is small and tightly coupled to `packer.setup`'s sequencing. Following the project rule that `init.lua` is the only file allowed to require multiple siblings, this is the right place.

## Implementation Phases

### Phase 1: Wire up the config field — make `colorscheme` actually read

1. **Add type annotations for `colorscheme`** (File: `lua/beast/libs/packer/config.lua`)
   - Action: Add `---@class Beast.Packer.Colorscheme` with `name` and `plugin` fields. Update `Beast.Packer.Config` to include `colorscheme?: Beast.Packer.Colorscheme`.
   - Why: Document the public shape; LSP autocomplete for users.
   - Depends on: None.
   - Risk: Low.

2. **Add helper `apply_early_colorscheme()` in packer init** (File: `lua/beast/libs/packer/init.lua`)
   - Action: Implement the helper exactly as described in Architecture Changes (steps 1–8). Use `vim.uv.fs_stat` for the existence check on the plugin and every entry of `spec.dependencies`. Use `pcall` around `state.load` and around `vim.cmd.colorscheme`. On error, restore `state.loaded_plugins[plugin] = nil` so the normal trigger can retry. Return the plugin name on success, `nil` otherwise.
   - Why: This is the actual feature.
   - Depends on: Step 1.
   - Risk: Medium — has to interleave correctly with the existing setup pipeline.

3. **Call helper inside `M.setup` at the right point** (File: `lua/beast/libs/packer/init.lua`)
   - Action: Invoke `local early_loaded = apply_early_colorscheme()` immediately **after** the existing classification loop (the one that fills `eager_specs`/`lazy_specs`/`manual_specs`) and **before** the `vim.api.nvim_create_autocmd("PackChangedPre", ...)` block. By this point: every spec has been normalized; `init()` has already run for each spec; `state.plugins` is fully populated; `eager_specs` is known. This satisfies all three rubber-duck blocking issues simultaneously.
   - Why: Correct sequencing — preserves the existing invariant that `init()` runs before any plugin's `config()`, and gives the helper full access to `state.plugins` for dep resolution.
   - Depends on: Step 2.
   - Risk: Low — clear sequencing rationale.

4. **Skip duplicate `config()` in the eager loop** (File: `lua/beast/libs/packer/init.lua`)
   - Action: In the "Step 5: Load eager plugins and run their config" loop near `init.lua:278`, change the guard from `if spec.config then` to `if spec.config and not state.loaded_plugins[spec.name] then`.
   - Why: Prevents `config()` from running twice for `lazy = false` colorschemes (rose-pine, tokyonight, catppuccin). Without this, `state.load` in Step 2 runs `config`, then the eager loop runs it again.
   - Depends on: Step 3.
   - Risk: Low — single-line guard addition; correct by inspection.

5. **Verify lazy triggers and `vim.pack.add` callback are unaffected** (File: `lua/beast/libs/packer/init.lua`)
   - Action: No change. Re-read both code paths to confirm both funnel through `state.load`, which short-circuits on `loaded_plugins[name]`. Document this in code with a one-line comment near the helper call site.
   - Why: Defense-in-depth check; documents the invariant for future readers.
   - Depends on: Step 4.
   - Risk: Low — comment-only.

### Phase 2: Surface the config through `beast.setup`

6. **Add `packer_config` to `Beast.Config` defaults** (File: `lua/beast/init.lua`)
   - Action: Add `packer_config = { colorscheme = nil }` to `defaults`. Update `Beast.Config` LDoc annotation with `packer_config?: Beast.Packer.Config`.
   - Why: Make the field reachable from the user's top-level `require("beast").setup({ ... })`.
   - Depends on: Phase 1.
   - Risk: Low.

7. **Call `packer.config.setup` from `beast.setup`** (File: `lua/beast/init.lua`)
   - Action: Add `require("beast.libs.packer.config").setup(cfg.packer_config or {})` right before `local packer = require("beast.libs.packer")`.
   - Why: Wire user-supplied `packer_config` into the packer config before `packer.setup(specs)` runs.
   - Depends on: Step 6.
   - Risk: Low.

### Phase 3: Verification

8. **Manual smoke test: `colorscheme = nil` (current behaviour)** (File: N/A)
   - Action: Restart nvim with no `packer_config` override. Confirm setup completes; previously-flashing default colorscheme behaviour is unchanged.
   - Why: Regression check.
   - Depends on: Phases 1–2.
   - Risk: Low.

9. **Manual smoke test: `colorscheme` set, plugin installed (lazy spec)** (File: `init.lua` (root) or via `:lua` REPL)
   - Action: Set `packer_config = { colorscheme = { name = "monokai-pro", plugin = "monokai-pro.nvim" } }`. Restart nvim. Confirm: (a) no flash, (b) `:colorscheme` returns `monokai-pro` immediately at startup, (c) `:lua =require("beast.libs.packer.state").loaded_plugins["monokai-pro.nvim"]` is `true` early in startup, (d) profile shows exactly **one** load event for the plugin with `reason.detail == "colorscheme"`.
   - Why: Verify the happy path for a lazy-triggered colorscheme.
   - Depends on: Step 8.
   - Risk: Low.

10. **Manual smoke test: `colorscheme` set, plugin is `lazy = false`** (File: N/A)
    - Action: Set `packer_config = { colorscheme = { name = "rose-pine", plugin = "rose-pine" } }`. Restart nvim. Confirm: (a) no flash, (b) the spec's `config()` is called **exactly once** (verify by adding a temporary `print` or by inspecting the profile — there should be a single `config_ms` measurement). This catches the rubber-duck Blocking #1 regression.
    - Why: The eager-loop guard (Step 4) is the fix for double-`config()`. Verify it works.
    - Depends on: Step 9.
    - Risk: Low.

11. **Manual smoke test: `colorscheme` set, plugin not installed** (File: N/A)
    - Action: Delete `~/.local/share/nvim/site/pack/core/opt/monokai-pro.nvim`. Restart nvim. Confirm: (a) no error, (b) plugin gets installed by `vim.pack.add`, (c) colorscheme eventually applies via the spec's normal trigger (`UIEnter` for monokai-pro), (d) no double-load (check `:Pack` UI / profile).
    - Why: Verify the skip-when-missing path.
    - Depends on: Step 10.
    - Risk: Low.

12. **Manual smoke test: bad shape** (File: N/A)
    - Action: Set `packer_config = { colorscheme = { plugin = "monokai-pro.nvim" } }` (missing `name`). Restart nvim. Confirm: warning notification, no error, setup continues normally.
    - Why: Verify input validation.
    - Depends on: Step 11.
    - Risk: Low.

13. **Manual smoke test: rollback on early-load failure** (File: N/A)
    - Action: Temporarily replace the colorscheme plugin's `config()` with `function() error("boom") end`. Restart nvim with `packer_config` set. Confirm: (a) `vim.notify` reports the error, (b) `state.loaded_plugins[plugin]` is `nil` after the helper returns (so the normal trigger can retry), (c) setup finishes without aborting.
    - Why: Verify the rollback path that mitigates the pre-existing `state.load` flag-leak bug.
    - Depends on: Step 12.
    - Risk: Low.

## Testing Strategy

- **Unit tests**: None — the project does not have a unit test harness for packer (see `lua/beast/libs/packer/test.lua` is interactive). Manual verification is the project's convention here.
- **Integration tests**: Manual smoke tests above (steps 7–10) cover the four key paths: nil, installed, missing, bad-shape.
- **Manual verification**: Use `:lua =require("beast.libs.packer.profile")` to confirm `monokai-pro.nvim` is loaded with `reason.type = "eager"` and `reason.detail = "colorscheme"`; this is the easiest signal that the early path fired.

## Risks & Mitigations

- **Risk**: Pre-existing bug in `state.load` — `loaded_plugins[name]` is set to `true` *before* `vim.cmd.packadd`, so a packadd failure leaves the flag stuck and the plugin can never load again that session. → **Mitigation**: The helper wraps `state.load` in `pcall` and explicitly clears `state.loaded_plugins[plugin] = nil` on error, so the normal trigger path (event/cmd/eager loop) can retry after the rest of `setup()` finishes installing or repairing the plugin. Fixing `state.load` itself is out of scope for this dev spec — that's a broader, unrelated change.
- **Risk**: `state.load` uses `Toast` (the global) — if `_G.Toast` is not yet set, it errors. → **Mitigation**: Verified: `_G.Toast = toast` is set in `beast/init.lua` (line 47) before `packer.setup` runs. Safe.
- **Risk**: Disk-existence check (`vim.uv.fs_stat`) gives a false positive if the directory exists but is corrupt/empty. → **Mitigation**: `state.load` is wrapped in `pcall`; a corrupt plugin causes a logged error and the rollback in the helper restores `loaded_plugins[plugin] = nil`. Acceptable.
- **Risk**: Colorscheme spec uses a `cond = function() return false end` filter and gets dropped from specs. → **Mitigation**: Helper is called *after* the cond filter runs, so `state.plugins[plugin]` will be missing and the helper returns `nil` silently. Correct behaviour.
- **Risk**: Spec for the colorscheme has `dependencies` whose plugin dirs are not yet installed. → **Mitigation**: Helper checks `fs_stat` for every dep and falls back to the normal install path if any dep is missing. Avoids a recursive `state.load` walk that would error out on the first missing dep.
- **Risk**: Other lazy triggers (`event`, `cmd`, `keys`, etc.) registered later for the early-loaded plugin. → **Mitigation**: All triggers funnel through `state.load`, which short-circuits on `loaded_plugins[name]`. No special-casing needed; documented in code via a comment at the helper call site.
- **Risk**: User sets `colorscheme.name` to a scheme the loaded plugin does not actually expose. → **Mitigation**: `pcall(vim.cmd.colorscheme, name)` swallows the error and logs nothing. The user gets the default colorscheme — same outcome as today. Fine.

## Success Criteria

- [ ] `Beast.Config` exposes `packer_config = { colorscheme = { name, plugin } }`.
- [ ] When `colorscheme` is `nil`, packer setup behaves identically to today.
- [ ] When `colorscheme` is set and plugin is installed, the colorscheme is visible at the very first paint of the Neovim window (no flash).
- [ ] When `colorscheme` is set and plugin is **not** installed, no error; plugin installs and loads through its normal trigger.
- [ ] No double-load: `state.loaded_plugins[plugin]` is `true` exactly once and `profile` shows a single load event.
- [ ] Bad shape (`name` or `plugin` missing) is reported via `vim.notify` and setup continues.

## ADR Required

No. This is a small feature addition that follows the existing config / state / load patterns. It does not introduce a new dependency, does not change auth/data/API design, and does not establish a new architectural pattern.
