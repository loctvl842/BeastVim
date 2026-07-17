---
name: packer-phase-profiling
description: "Packer Phase Profiling"
generated: 2026-05-06
---

# Dev Spec: Packer Phase Profiling

## Summary

Close the two highest-value attribution gaps in `beast.libs.packer.setup` by
recording phase-level timings for `vim.pack.add` (Step 4) and
`apply_early_colorscheme` (the new step added before Step 4). Both phases run
on the startup critical path and neither is currently visible to either
profiler. The fix: extend the existing `beast.libs.packer.profile.measure`
API with a new "phase" target table — same call signature, just a different
storage map — and wrap the two call sites in `packer/init.lua`.

After this lands, a health check that runs `BEAST_PROFILE=1` will be able to
say *exactly* how many milliseconds each setup phase contributed, instead of
having to infer it from the gap between `packer.setup` self time and the sum
of per-plugin `packadd_ms`/`config_ms`. This is the gap that bit us in the
last bench (`packer.setup` self time inflated 3.7 → 12.2 ms with a
`vim.schedule` wrapper, with no way to attribute the regression).

## Requirements

- `beast.libs.packer.profile` exposes a phase-level recording table, addressable
  by phase name, recording `ms`, `calls`, `min`, `max`.
- The existing `profile.measure(plugin_name, field, fn)` signature is reused —
  same arity, same return shape (`ok, err`). A new value of `field`
  (`"phase_ms"`) routes the timing into the phase table instead of the
  per-plugin profile table.
- Two phases recorded in `M.setup`:
  - `pack_add` — wraps the entire `vim.pack.add(...)` call in Step 4 (inside
    the existing `xpcall`).
  - `early_cs` — wraps the existing `apply_early_colorscheme()` call in the
    `vim.schedule` block.
- Phase recording **must not double-count** with per-plugin `packadd_ms` /
  `config_ms` — the existing per-plugin measurements remain unchanged.
- Phase recording **must not change** any user-visible behaviour: same load
  order, same error handling (`xpcall` for `pack_add`, silent skip for
  `early_cs`), same return values from `M.setup`.
- `health-config.md` gains two new rows in the alert thresholds table.

## Out of scope

- Wrapping `import.expand_imports`, the init() loop, the eager config loop,
  or the lazy-trigger registration loop. Those are Phase 2 / a future spec.
- Adding a `scripts/bench-packer-setup.lua` benchmark script.
- Adding a `:checkhealth beast.packer` provider that surfaces phase numbers.
- Renaming or deprecating the existing `packadd_ms` / `config_ms` fields.
- Changing the top-level `lua/beast/profile.lua` — that wraps `M.*` table
  methods and remains unchanged.

## Research

### Repo Search

- Searched for: `profile.measure`, `Util.hrtime`, `hrtime`, `phases?` (in
  packer lib).
- Found:
  - `lua/beast/libs/packer/profile.lua` — owns `profiles` table (per-plugin)
    and exposes `methods.add_time`, `methods.measure`, `methods.set_reason`,
    `methods.iter`. Read-only metatable proxy at module level.
  - `lua/beast/libs/packer/state.lua:90,106` — only existing call sites for
    `profile.measure` (records `packadd_ms` and `config_ms` per plugin during
    `state.load`).
  - `lua/beast/libs/packer/init.lua:223,357` — also call `profile.measure`
    (init step + eager config step), recording into `config_ms` per plugin.
  - `lua/beast/util/init.lua:35` — `Util.hrtime()` is the canonical timer
    used everywhere in packer (`profile.lua`, `operation.lua`, `ui.lua`).
  - `lua/beast/profile.lua` (top-level) — wraps `M.*` methods of any
    `beast.libs.*` / `beast.plugins.*` module. Will not see local helpers
    like `apply_early_colorscheme` or inline calls like `vim.pack.add`. So
    the lib-internal profile is the right place to add this.
- Reuse opportunity: **Adopt** — `profile.measure` is already the established
  pattern (3 call sites). Extending it with a phase target keeps the API
  surface uniform.

### Package Search

- Searched: native Neovim API for built-in phase profiling.
- Found: `vim.uv.hrtime()` (already wrapped by `Util.hrtime`). No native
  phase-aware profiler exists.
- Decision: **Adopt** — extend the existing `beast.libs.packer.profile`
  module. No new dependencies.

## Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/libs/packer/profile.lua` | Modify | Add `phases` table, `Beast.Packer.PhaseProfile` class, route `measure(..., "phase_ms", ...)` calls into `phases` instead of `profiles`. Expose `phases` via metatable. |
| `lua/beast/libs/packer/init.lua` | Modify | Wrap `vim.pack.add` (Step 4) and `apply_early_colorscheme()` (in the `vim.schedule` block) with `profile.measure(name, "phase_ms", fn)`. |
| `docs/tec-config/health-config.md` | Modify | Add two rows to the *Alert Thresholds* table for `pack_add_ms` and `early_cs_ms`. |

## Implementation Phases

### Phase 1: Phase profiling (only phase) — record `pack_add` and `early_cs`

1. **Add `Beast.Packer.PhaseProfile` type and `phases` table to lib-internal profile**
   (File: `lua/beast/libs/packer/profile.lua`)
   - Action: At the top of the file alongside `Beast.Packer.LoadProfile`,
     add:
     ```lua
     ---@class Beast.Packer.PhaseProfile
     ---@field ms    number   total milliseconds across all calls
     ---@field calls integer  number of times this phase was measured
     ---@field min   number   min single-call ms
     ---@field max   number   max single-call ms
     ```
   - Add a parallel storage table: `local phases = {} ---@type table<string, Beast.Packer.PhaseProfile>`.
   - Why: Separates phase-level data from per-plugin data so neither shape
     leaks into the other. A health-check report can iterate each table
     independently. (Requirement: phase recording must not double-count.)
   - Depends on: None
   - Risk: Low — additive only.

2. **Add `methods.add_phase_time` private helper**
   (File: `lua/beast/libs/packer/profile.lua`)
   - Action: Mirror `methods.add_time` but write into `phases`:
     ```lua
     ---@private
     function methods.add_phase_time(name, delta_ms)
         local p = phases[name] or { ms = 0, calls = 0, min = math.huge, max = 0 }
         p.ms = p.ms + delta_ms
         p.calls = p.calls + 1
         if delta_ms < p.min then p.min = delta_ms end
         if delta_ms > p.max then p.max = delta_ms end
         phases[name] = p
     end
     ```
   - Why: Keeps the per-plugin `add_time` untouched while reusing its idiom.
   - Depends on: Step 1
   - Risk: Low

3. **Route `measure(name, "phase_ms", fn)` into the new helper**
   (File: `lua/beast/libs/packer/profile.lua`)
   - Action: In `methods.measure`, branch on `field`:
     ```lua
     function methods.measure(name, field, fn)
         local t0 = Util.hrtime()
         local ok, err = pcall(fn)
         local t1 = Util.hrtime()
         if ok then
             local delta_ms = (t1 - t0) / 1e6
             if field == "phase_ms" then
                 methods.add_phase_time(name, delta_ms)
             else
                 methods.add_time(name, field, delta_ms)
             end
         end
         return ok, err
     end
     ```
   - Why: Same call signature as today (Requirement). Existing
     `packadd_ms`/`config_ms` call sites are unaffected because their `field`
     value is unchanged.
   - Depends on: Step 2
   - Risk: Low — the branch only triggers on the new field value.

4. **Expose `phases` via the read-only metatable**
   (File: `lua/beast/libs/packer/profile.lua`)
   - Action: In the module's `__index`, add a check so that `profile.phases`
     returns the `phases` table reference (or a snapshot, but a reference is
     consistent with how `profile.iter` exposes per-plugin state):
     ```lua
     __index = function(_, key)
         if methods[key] ~= nil then return methods[key] end
         if key == "phases" then return phases end
         return profiles[key]
     end,
     ```
   - Why: Reports / health checks need to read the table without going
     through `iter()`.
   - Depends on: Step 3
   - Risk: Low — additive metatable branch.

5. **Wrap `vim.pack.add` in Step 4 of `M.setup`**
   (File: `lua/beast/libs/packer/init.lua`)
   - Action: In Step 4, wrap the body of the existing `xpcall`:
     ```lua
     local packadd_ok, packadd_err = xpcall(function()
         profile.measure("pack_add", "phase_ms", function()
             vim.pack.add(vim_pack_specs, {
                 confirm = false,
                 load = function(plugin) ... end,
             })
         end)
     end, debug.traceback)
     ```
   - Why: Captures the heaviest single call in setup. The wrapping is inside
     the existing `xpcall` so the traceback flow is unchanged on failure.
   - Caveat: `profile.measure` only records on `ok == true`, so a failed
     `vim.pack.add` does not contribute to `phases.pack_add` — matches how
     per-plugin `packadd_ms` already behaves on packadd failure.
   - Depends on: Step 4
   - Risk: Low — same control flow, one extra closure depth.

6. **Wrap `apply_early_colorscheme()` inside the `vim.schedule` block**
   (File: `lua/beast/libs/packer/init.lua`)
   - Action: Replace the current call with:
     ```lua
     vim.schedule(function()
         profile.measure("early_cs", "phase_ms", apply_early_colorscheme)
     end)
     ```
   - Why: Captures the new feature's cost. Because the call is deferred via
     `vim.schedule`, the timing reflects only the work done inside the
     callback (cheap state.load + colorscheme apply), not the schedule queue
     time. That's what we want.
   - Depends on: Step 4
   - Risk: Low — same closure shape; the `apply_early_colorscheme` early-return
     path (when `cs == nil`) means a no-op cost of ~0 ms.

7. **Add packer phase thresholds to the health config**
   (File: `docs/tec-config/health-config.md`)
   - Action: Append two rows to the *Alert Thresholds* table:
     ```
     | `beast.packer.profile.phases.pack_add.ms` | > 30 ms | > 60 ms |
     | `beast.packer.profile.phases.early_cs.ms` | > 10 ms | > 20 ms |
     ```
   - Why: Without thresholds the new metrics are unactionable. Numbers chosen
     to match the existing "single sourcing event" tier (30/60) for
     `pack_add` and the existing `*.setup self time` tier (10/20) for the
     lighter `early_cs` step.
   - Depends on: Steps 5 and 6 (the metric must exist before we threshold
     it).
   - Risk: Low — documentation only.

## Testing Strategy

- **Unit tests**: `tests/` is currently empty (standing process gap per
  health-config). Adding tests for this 1-file change is out of scope; flag
  remains.
- **Bench**: No new bench script. The verification is to run the existing
  health-check methodology and inspect the new fields.
- **Manual verification (headless)**:
  ```bash
  out="$HOME/.cache/BeastVim/beast-profile.txt"
  rm -f "$out"
  BEAST_PROFILE=1 BEAST_PROFILE_OUT="$out" \
    NVIM_APPNAME=BeastVim nvim --headless \
    -c 'autocmd VimEnter * call timer_start(0, {-> execute("qa!")})'
  # also dump phases
  NVIM_APPNAME=BeastVim nvim --headless \
    -c 'lua local p = require("beast.libs.packer.profile"); print(vim.inspect(p.phases))' \
    -c 'qa!'
  ```
  Expected: `phases.pack_add` and `phases.early_cs` populated with `ms`,
  `calls = 1`, `min`, `max`. `phases.early_cs.ms` is near zero when
  `colorscheme = nil`, non-zero when a real colorscheme is configured.

- **Regression check**: Re-run the 10× cold-start startup bench used in the
  most recent health report. Mean must stay within ±15 % of the previous
  recorded mean (tighter than the alert threshold because this change is
  expected to add ≤ 1 ms of `Util.hrtime()` overhead).

## Risks & Mitigations

- **Risk**: The new `field == "phase_ms"` branch in `measure` is reachable by
  any caller — a typo like `profile.measure("foo", "phase_ms", fn)` from
  somewhere outside packer would silently go into `phases`. → **Mitigation**:
  `profile.lua` is lib-internal (only required from inside `beast.libs.packer.*`),
  and the metatable `__newindex` already errors on direct mutation. The risk
  surface is the same as today's `packadd_ms`/`config_ms` typos.
- **Risk**: `Util.hrtime()` cost added per phase. → **Mitigation**: Two
  additional calls per setup is sub-microsecond on macOS/Linux; absolutely
  noise-floor.
- **Risk**: Bench noise on this machine (std 4–7 ms) makes a 1 ms regression
  invisible until many runs. → **Mitigation**: This is an existing bench
  problem, not introduced by this change. Mean of 10 with the previous
  recorded mean is the comparison anchor.
- **Risk**: A future caller adds a phase name that collides with a real
  plugin name (e.g. a plugin literally named `pack_add`). → **Mitigation**:
  `phases` is a separate map from `profiles`; namespaces don't collide. The
  only collision would be in metatable `__index`: `profile.pack_add` would
  hit `phases` first and shadow a `profiles.pack_add` (since `phases`
  precedes `profiles` in the proposed lookup). Document the convention:
  phase names use snake_case and avoid known plugin names. Acceptable risk.

## Completed

2026-05-04 — Phase 1 implemented:
- `lua/beast/libs/packer/profile.lua` — added `Beast.Packer.PhaseProfile`,
  `phases` table, `methods.add_phase_time`, branched `methods.measure` on
  `field == "phase_ms"`, exposed `phases` via metatable.
- `lua/beast/libs/packer/init.lua` — wrapped `vim.pack.add` (Step 4) with
  hoisted-timing pattern (timing outside `xpcall` to preserve traceback
  contract; the spec's prescribed `xpcall(profile.measure(...))` was caught
  by `tec-review` as silent-error-swallowing). Wrapped
  `apply_early_colorscheme()` with `profile.measure("early_cs", "phase_ms",
  ...)`. The `vim.schedule` wrapper from the prior feature was reverted by
  the user before implementation; the wrap is correct synchronously.
- `docs/tec-config/health-config.md` — added `phases.pack_add.ms` (30/60)
  and `phases.early_cs.ms` (10/20) thresholds to the Alert Thresholds table.
- `docs/CODEMAP/libraries.md` — updated packer section to mention phases
  and the `colorscheme` opt.

Verification:
- `luac -p` clean for both files.
- Headless smoke test: `phases.pack_add` and `phases.early_cs` populate.
- Error-path test: simulated `error()` inside `xpcall` body confirms
  `packadd_ok = false` propagates and `add_phase_time` is NOT called on
  failure (counter stays at 1).
- 10-run cold-start bench: mean 34.13 ms, std 4.01 ms — within ±15% of
  prior 35.83 ms baseline.
- Per-plugin profile regression check: `monokai-pro` profile still records
  `packadd_ms`/`config_ms`/`total_ms` unchanged.

`tec-review`: PASS on second pass after BLOCK fix.

ADR: not required (stays within existing per-lib profile pattern; no
architectural shift).
