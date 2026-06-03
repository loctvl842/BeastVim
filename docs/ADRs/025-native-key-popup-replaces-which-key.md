# ADR-025: Native Press-and-Wait Popup Replaces which-key.nvim

**Status:** Accepted

**Date:** 2026-06-03

**Evidence:** Dev spec `docs/dev-specs/key-press-and-wait-popup.md`; files under `lua/beast/libs/key/` (especially `popup.lua` ~600 LOC); deletion of `which-key.nvim` spec from `lua/beast/plugins/init.lua`; comment update in `lua/beast/option.lua:34`; bench `scripts/bench-key-popup.lua`; related: ADR-009 (native statusline replaces heirline), ADR-018 (native scroll replaces neoscroll), ADR-022 (native git replaces gitsigns).

## Context

BeastVim used `which-key.nvim` for one thing: the **press-and-wait popup** that appears after `<leader>`/`<localleader>` to show available continuations. Everything else which-key offers (marks/registers/spelling popups, preset labels for `g`/`z`/operators) was already disabled in the project's wk config.

The project already maintains its own keymap registry in `lua/beast/libs/key/core.lua`:

- `Key.safe_set(mode, lhs, rhs, opts)` is the sole sanctioned write path.
- `Key.managed` is a single in-memory source of truth for every keymap BeastVim sets.
- `BeastKeysChanged` `User` autocmd already fires on every set/del.

Despite this, which-key was paying ongoing cost because Neovim does not expose a `KeymapChanged` autocmd:

- which-key cannot trust any cache, so it scrapes `nvim_get_keymap` + `nvim_buf_get_keymap` on `BufReadPost` / `LspAttach` / `wk.add()` / `ModeChanged`.
- It registers `vim.keymap.set` trigger maps for every prefix × every buffer × every mode (dozens–hundreds per buffer).
- A 50 ms polling timer (`state.lua:156-164`, with a `HACK` comment) compensates for `ModeChanged` unreliability.
- The popup occasionally fails to show even when the keymap fires — observed on the user's setup.

BeastVim's registry gives us a stable, externally observable cache that which-key cannot use without invasive integration. Building the popup natively on top of `Key.managed` removes the entire per-buffer scrape/register layer.

## Decision

Build `lua/beast/libs/key/popup.lua` as a focused native press-and-wait popup. Drop `which-key.nvim` from the plugin manifest. The popup:

- Reads `Key.managed` as its prefix tree source — no `nvim_get_keymap` scrape, no per-buffer rebuilds.
- Caches the tree lazily; invalidates on `BeastKeysChanged`. O(1) cache invalidation.
- Registers exactly **two trigger keymaps** globally (`<leader>`, `<localleader>` × `n`, `x`) at setup, never per-buffer.
- Filters per-buffer at render time by inspecting `keys.buffer` on the cached registry entries (normalised in `core.M.set`).
- Helix-strict layout: bottom-right anchored float, breadcrumb title, direct children only.
- Suspends the trigger keymap before `nvim_feedkeys("…", "m", false)` and re-registers on the next `vim.schedule` tick, so `<cmd>`, `<Plug>`, expr, silent, function-rhs all resolve through Neovim's normal resolver (no behaviour drift from direct callback invocation).
- Subclasses `Beast.View` (ADR-001) and uses the `BeastKey*` highlight namespace (ADR-008).

Enabled by default. Opt-out with `Key.setup({ popup = { enabled = false } })`.

## Alternatives Considered

1. **Keep `which-key.nvim`.** Battle-tested, full-featured, supports operators/marks/registers/spelling popups we don't use. Rejected because (a) the only feature we use is the press-and-wait popup, (b) its caching model fights the project's centralised registry — every BeastVim keymap change emits `BeastKeysChanged`, which which-key cannot listen to in a perf-safe way; instead it scrapes, and (c) the popup intermittently fails to render even when the keymap fires.

2. **Bridge `Key.managed` → which-key via `wk.add()`.** This was the *prior* approach (visible in the deleted `lua/beast/plugins/init.lua` block that listened to `BeastKeysChanged` and called `wk.add` incrementally). Rejected because the bridge does not stop which-key from doing its own scrape and per-buffer trigger registration — it only adds rows. The perf overhead is paid regardless.

3. **Use `mini.clue`.** Smaller than which-key, also press-and-wait. Rejected for the same fundamental reason: any external popup library has to maintain its own keymap mirror because Neovim lacks a `KeymapChanged` autocmd; we already maintain that mirror as a first-class registry.

4. **A `vim.on_key` global handler that snoops every keypress.** Rejected — `on_key` cannot intercept (only observe), and it would pay the cost of *every* keypress, not just leader-prefixed ones.

## Rationale

1. **Match the "port the design, not the plugin" precedent.** ADR-009 (statusline), ADR-018 (scroll), ADR-022 (git) all do this. The slice we use is small; the slice the upstream plugin maintains is large.

2. **The slice is small.** Press-and-wait popup + visual selection preservation + count/register preservation + recursion guard + macro safety is ~600 LOC including doc comments and the `_internal` bench/test hooks. which-key is ~2 000 LOC for the popup feature alone.

3. **The registry IS the cache.** which-key's central problem is that no `KeymapChanged` autocmd exists in Neovim. BeastVim's `Key.safe_set` is the only sanctioned write path, so `Key.managed` is always coherent and `BeastKeysChanged` is emitted on every change. Cache invalidation collapses from "scrape + diff on every autocmd that might have changed something" to a single line: `index_cache = nil`.

4. **No per-buffer trigger registration.** Only two keymaps registered globally at setup. which-key registers per-prefix × per-buffer × per-mode (often 50–200 per buffer) because it has no other way to honour `nowait`. Our triggers are global; buffer-locality is handled by filtering `keys.buffer` on read.

5. **Bench targets met by 3–18×.** Spec thresholds: index build < 500 µs, popup open < 5 ms. Measured: index build p50 = 254 µs, popup open p50 = 1.5 ms.

6. **Resolution correctness for free.** By feeding the full sequence through `nvim_feedkeys` with the trigger temporarily removed, `<cmd>`/`<Plug>`/expr/silent/function-rhs all resolve through Neovim's normal resolver — no second-system effect.

## Consequences

**Positive**
- One fewer runtime dependency loaded at startup.
- Popup is deterministic — no 50 ms polling timer, no per-buffer scrape, no `ModeChanged` HACK.
- `Key.managed` becomes the documented contract for "where do my keymaps live"; any future feature (e.g. a fuzzy keymap finder, `:checkhealth beast.key`) can read from the same registry without scraping.
- Architectural symmetry with ADR-009/018/022 (native replacements).

**Negative**
- Loss of which-key side features: marks (`'`), registers (`"`), spelling (`z=`) popups, operator/motion/textobject preset labels. These were already disabled in the user's config; flagged in spec § Out of scope so the user understands the trade.
- Keymaps registered via `vim.keymap.set` directly (bypassing `Key.safe_set`) do not appear in the popup — they still fire (feedkeys goes through Neovim's resolver), just invisible to the index. Acceptable contract: use `Key.safe_set` for anything you want browsable.
- Default `popup.enabled = true` ships without a manual-verification gate. Mitigation: collision check (`vim.fn.maparg`) skips registration with a `vim.notify` warning if any other map already owns the trigger; opt-out via `Key.setup({ popup = { enabled = false } })`.

**Neutral**
- The full-screen keymap browser at `lua/beast/libs/key/ui.lua` is unaffected. Different feature, different entry point.
- `to_which_key` / `to_which_key_spec` exporters in `lua/beast/libs/key/init.lua` are removed (dead code post-cutover). Personal-config acceptable risk.

## Follow-ups

- If LSP-specific buffer-local popups are needed later, register on-demand triggers from `LspAttach` (Design B from spec § Out of scope). Not needed today.
- If operator-pending mode popups become useful, extend `loop()` to capture register/count/operator. Out of scope for this iteration.
