---
name: packer-builtin-plugins
description: Flag plugins that ship with BeastVim by default, badge them in the Packer UI, and block their deletion
generated: 2026-08-02
---

> PM Spec: [docs/pm-specs/packer-builtin-plugins.md](../pm-specs/packer-builtin-plugins.md)

# Summary

Move `blink.cmp`'s full plugin spec into a new `lua/beast/libs/packer/builtin.lua`
in the `packer` lib - anything defined there *is* builtin by virtue of living
in that file, no separate name-matching list. `packer.setup()` merges those
specs in and stamps `builtin = true` on each, then consumes that flag in two
places in the existing dashboard UI: a new badge (reusing the lib-badge
rendering pattern) and a new delete-guard branch (reusing the lib-block toast
pattern).

---

# Context

## Problem
`Beast.Packer.PluginSpec` (`lua/beast/libs/packer/state.lua:9-21`) has no
concept of "ships with BeastVim by default." Every plugin registered via
`state.plugins[spec.name] = spec` (`lua/beast/libs/packer/init.lua:257`) is
indistinguishable from any other once it's in the registry, so the dashboard's
`delete_plugin` handler (`ui.lua:1428-1439`) deletes `blink.cmp` exactly as
readily as any plugin the user added themselves - there's no data to check
against, let alone a UI signal.

### Solution
`blink.cmp`'s full spec (`src`, `version`, `dependencies`, `lazy`, `config`)
moves verbatim out of `lua/beast/plugins/init.lua` into a new
`lua/beast/libs/packer/builtin.lua`, typed `Beast.Packer.PluginSpec[]`. Inside
`packer.setup()`, right after `local specs = config.spec`, a merge step
`require()`s `builtin.lua`, stamps `builtin = true` on each returned spec, and
prepends them to the user's own spec list before import expansion continues
as normal. `state.lua`'s `PluginSpec` annotation gains a `builtin?` field.
`ui.lua`'s Loaded/Not Loaded render loops gain a third branch (alongside the
existing "is a lib" / "plain" branches) that draws a new `★` badge
(`config.ui.icons.builtin`) when `spec.builtin` is true. `delete_plugin` gains
one guard clause, mirroring the existing `kind == "lib"` guard, that blocks
deletion and shows a toast when `state.plugins[name].builtin` is true.
`update_plugin` is untouched - builtin plugins update exactly like any other.

**Timing constraint**: `builtin.lua`'s `blink.cmp` spec calls `gh(...)` and
references `Icon.kinds`/`Icon.brain` at table-construction time. `_G.gh` and
`_G.Icon` aren't set until `beast.setup()` (`lua/beast/init.lua`) reaches the
lines that assign them - which happens *after* `require("beast.libs.packer")`
already ran (`lua/beast/init.lua:38`, the module's first require, well before
`_G.gh` is set at line 427). So `builtin.lua` must be `require()`d from
*inside* `packer.setup(opts)`, never at `packer/init.lua`'s file-top-level -
matching how the existing flat plugin list already avoids this by being
lazily required through `import.expand_imports` deep inside `setup(opts)`.

---

# Research

### Repo Search
- Searched for: `builtin`, `blink.cmp`, `state.libs\[`, `get_plugin_at_cursor`,
  and any packer test/bench file (`find -iname "*test*packer*"`,
  `*bench*packer*`).
- Found: no existing `builtin`/`protected`/`is_lib`-style flag on plugin specs
  anywhere; no packer-specific test file (`tests/test-*.lua`) or bench script
  (`scripts/bench-*.lua`) exists today. `get_plugin_at_cursor`
  (`ui.lua:1291-1326`) already parses rows as "2nd token, else 3rd token"
  specifically to handle badge-prefixed rows (built for the `lib` badge) - a
  builtin badge fits that same 3-token layout with **zero changes** to that
  function (verified by tracing both row layouts by hand).
- Reuse opportunity: Yes - reuse the lib-badge render branch
  (`state.libs[spec.name]` check in the Loaded/Not Loaded loops) and the
  lib-block toast pattern (`"<name> is a library and can't be deleted"`) in
  `delete_plugin`.

### Built-in / Existing Lib Check
- Checked: `state.lua` (`PluginSpec`, `M.plugins`/`M.libs` registries),
  `config.lua` (`icons` defaults, `config.spec`), `import.lua` (spec
  expansion - confirms plain, non-`import` specs pass through untouched, so
  a spec merged in before `import.expand_imports()` runs keeps any field
  stamped on it, including `builtin`), `ui.lua` (render loops,
  `get_plugin_at_cursor`, `delete_plugin`/`update_plugin`), `init.lua`
  (`M.setup`'s spec-assembly pipeline, and `lua/beast/init.lua`'s own
  `M.setup` for the `_G.gh`/`_G.Icon` assignment order relative to
  `require("beast.libs.packer")`).
- Found: the plugin-vs-library split is structurally identical to what this
  feature needs, just missing the "builtin" middle tier. `import.lua`'s
  pass-through behavior means tagging specs *before* expansion is sufficient
  - no changes to `import.lua` itself are needed.
- Decision: **Build** - move `blink.cmp`'s spec into `builtin.lua`, merge and
  tag it inside `packer.setup()`, then reuse the lib-badge/lib-block pattern
  already in the codebase for the UI half.

---

# Architecture Changes

- **New file**: `lua/beast/libs/packer/builtin.lua` - returns
  `Beast.Packer.PluginSpec[]`, the full spec(s) of plugins that ship with
  BeastVim by default (starting with `blink.cmp`, moved here verbatim).
- **Modified**: `lua/beast/plugins/init.lua` - remove the `blink.cmp` spec
  block (now lives in `builtin.lua` instead).
- **Modified**: `lua/beast/libs/packer/state.lua` - add
  `---@field builtin? boolean` to the `Beast.Packer.PluginSpec` annotation
  (doc-only; no runtime code change).
- **Modified**: `lua/beast/libs/packer/init.lua` - inside `M.setup(opts)`,
  right after `local specs = config.spec`, merge in `builtin.lua`'s specs
  (deep-copied, each stamped `builtin = true`) ahead of the user's own specs,
  before `import.expand_imports` runs.
- **Modified**: `lua/beast/libs/packer/config.lua` - add a `builtin` icon
  (`"★ "`) next to the existing `lib` icon in `icons` defaults.
- **Modified**: `lua/beast/libs/packer/ui.lua` - three call sites:
  1. Loaded section render loop (~509-531): add a `spec.builtin` branch.
  2. Not Loaded section render loop (~551-565): same branch.
  3. `_actions_handler.delete_plugin` (~1428-1439): add a builtin guard
     clause after the existing `kind == "lib"` guard.

## Implementation Phases

## Phase 1: Data model — builtin.lua owns the full plugin spec
1. **Move `blink.cmp`'s spec into `builtin.lua`** (Files:
   `lua/beast/libs/packer/builtin.lua` new, `lua/beast/plugins/init.lua` modified)
   - Action: Cut the entire `{ name = "blink.cmp", src = gh(...), ... }`
     block verbatim out of `lua/beast/plugins/init.lua` into a new
     `lua/beast/libs/packer/builtin.lua`, typed `---@type Beast.Packer.PluginSpec[]`
     and wrapped in an array so more builtin entries can be added the same
     way later. Remove the block from `lua/beast/plugins/init.lua`.
   - Why: Anything defined in `builtin.lua` is builtin by construction - no
     separate name-matching list to keep in sync with the real spec.
   - Depends on: None
   - Risk: Low

2. **Add the `builtin` field to `PluginSpec`** (File: `lua/beast/libs/packer/state.lua`)
   - Action: Add `---@field builtin? boolean` under the existing `version`
     field in the `Beast.Packer.PluginSpec` annotation (`state.lua:21`).
   - Why: Documents the new flag for LSP/type-checking; no runtime behavior.
   - Depends on: None
   - Risk: Low

3. **Merge and stamp builtin specs during setup** (File: `lua/beast/libs/packer/init.lua`)
   - Action: Inside `function M.setup(opts)`, right after
     `local specs = config.spec` (line ~219), add:
     ```lua
     local builtin_specs = vim.deepcopy(require("beast.libs.packer.builtin"))
     for _, spec in ipairs(builtin_specs) do
       spec.builtin = true
     end
     specs = vim.list_extend(builtin_specs, specs)
     ```
     `require("beast.libs.packer.builtin")` must happen here - inside
     `M.setup`, not at file-top-level - because `blink.cmp`'s spec calls
     `gh(...)`/reads `Icon.*` at table-construction time, and those globals
     aren't set until `beast.setup()` reaches that point (see Context's
     "Timing constraint"). `vim.deepcopy` prevents `vim.list_extend` from
     mutating the cached module table that `require` would keep returning on
     any later `require("beast.libs.packer.builtin")` call.
   - Why: This is the one place to merge framework-level specs into the
     pipeline before `import.expand_imports` runs; since `import.lua` passes
     plain (non-`import`) specs through untouched, the `builtin = true`
     stamp survives expansion, normalization, and registration unchanged.
   - Depends on: Step 1
   - Risk: Low

## Phase 2: UI — badge and delete guard
1. **Add the builtin icon** (File: `lua/beast/libs/packer/config.lua`)
   - Action: Add `builtin = "★ ", -- ships with BeastVim by default; blocks delete`
     next to the existing `lib = "󰂖 ", ...` line (`config.lua:38`).
   - Why: Follows the existing icon-table convention; keeps all dashboard
     glyphs centrally configurable like every other icon.
   - Depends on: None
   - Risk: Low

2. **Render the builtin badge in Loaded/Not Loaded** (File: `lua/beast/libs/packer/ui.lua`)
   - Action: In both render loops (Loaded ~509-531, Not Loaded ~551-565),
     change the existing two-way `if state.libs[spec.name] then ... else ...`
     branch into a three-way branch: keep the `lib` case first, add
     `elseif spec.builtin then` using `config.ui.icons.builtin` with the same
     `" " .. icon .. " "` + status-icon layout as the lib branch, then fall
     through to the existing plain-row `else`.
   - Why: Reuses the exact rendering shape already proven for the lib badge -
     no new segment-building logic, just a new icon source.
   - Depends on: Phase 1 Step 3, Phase 2 Step 1
   - Risk: Low
   - Note: also update the stale doc comment above `get_plugin_at_cursor`
     (`ui.lua:1287-1290`) to mention builtin rows alongside lib rows in the
     "3rd token" case - no functional change, the parsing already handles it.

3. **Block delete for builtin plugins** (File: `lua/beast/libs/packer/ui.lua`)
   - Action: In `_actions_handler.delete_plugin` (~1428-1439), after the
     existing `if kind == "lib" then ... end` block, add:
     ```
     local spec = state.plugins[name]
     if spec and spec.builtin then
       Toast(name .. " is a builtin plugin and can't be deleted", vim.log.levels.WARN, { title = "BeastVim" })
       return
     end
     ```
   - Why: Matches the PM spec's exact toast wording and the existing
     no-confirmation, immediate-block pattern used for library rows.
   - Depends on: Phase 1 Step 3
   - Risk: Low
   - Note: `_actions_handler.update_plugin` is intentionally left unchanged -
     the PM spec requires `u` to work normally on builtin plugins.

---

# Testing Strategy
- Headless tests: none exist for `packer` today (confirmed via repo search);
  none added here per CLAUDE.md's "no speculative work" - this is a small,
  directly-observable UI change better covered by the manual scenarios below
  than by inventing a first test harness as a side effect.
- Bench: no packer-specific bench script exists. Per `DEVELOPMENT.md`'s quick
  start, run `./scripts/bench-startup.sh` once after Phase 1 (an added
  `require()` + a per-spec set lookup in the setup path) as a sanity check
  that startup time is unaffected - not expected to show any measurable
  delta, but it's the correct existing tool for this class of change.
- Manual: open the Packer dashboard (`:Pack` or configured command) after
  each phase and walk PM spec Scenarios 1-5
  (`docs/pm-specs/packer-builtin-plugins.md`):
  1. Confirm `blink.cmp` shows the `★` badge in Loaded (and in Not Loaded, by
     temporarily testing with a not-yet-loaded builtin plugin if needed).
  2. Press `x` on `blink.cmp` → toast, no deletion.
  3. Press `u` on `blink.cmp` → update proceeds normally.
  4. Press `x` on an ordinary plugin (e.g. `gitsigns.nvim`) → deletes as before.
  5. Press `x` then `u` on a library row (e.g. `explorer`) → both still
     blocked with their existing messages, confirming no regression.

---

# Success Criteria
- [ ] `blink.cmp` (and any name added to `builtin.lua`) shows the `★` badge
      in both Loaded and Not Loaded sections.
- [ ] Pressing `x` on a builtin plugin shows
      `"<name> is a builtin plugin and can't be deleted"` and does not delete it.
- [ ] Pressing `u` on a builtin plugin updates it with no special-casing.
- [ ] Non-builtin plugins are unaffected by `x`/`u`.
- [ ] Library rows are unaffected (`x`/`u` still both blocked with their
      existing messages).
- [ ] `./scripts/bench-startup.sh` shows no meaningful regression after Phase 1.
