# ADR-032: Native Autopairs Library (`mini.pairs` Rejected After Same-Day Trial)

**Status:** Accepted

**Date:** 2026-06-08

**Evidence:** Dev spec `docs/dev-specs/autopairs-library.md`; files under `lua/beast/libs/autopairs/`; commits `f348436` (Phase 1 — engine + 53 tests), `2c893d0` (Phase 2 — skip rules + 28 tests), `ad11759` (Phase 3 — wire-up, health, cutover); related: ADR-009 (native statusline), ADR-018 (native scroll), ADR-022 (native git), ADR-025 (native key popup), ADR-026 (pure highlight contract), ADR-029 (native LSP infra).

## Context

BeastVim had **no autopairs** at the start of the day. After analyzing LazyVim's setup (`mini.pairs` + a ~45-line monkey-patch adding `skip_next`/`skip_ts`/`skip_unbalanced`/`markdown` vetoes), we briefly adopted the same approach: added `nvim-mini/mini.pairs` to `lua/beast/plugins/init.lua` with the LazyVim-style wrapper inlined.

Within a few hours we reversed that decision. This ADR records the reversal and the rebuild.

The smart veto layer is the *only* part anyone interacts with — the engine underneath (~250 LOC of mostly-pure Lua: a pair registry, neighborhood matcher, five `<expr>` action functions, and a keymap installer) is mechanical and self-contained.

## Decision

Build `lua/beast/libs/autopairs/` as a native autopairs library covering the full surface:

- **Engine**: pair registry; `open`/`close`/`closeopen`/`bs`/`cr` action functions returning keystroke strings; `<expr>` mappings installed via `Key.safe_set` with a `{mode, lhs}` registry for idempotent install/uninstall.
- **Smart vetoes**: `skip_next` (Lua pattern), `skip_ts` (treesitter capture list), `skip_unbalanced` (line-local count), `markdown` (triple-backtick fence expansion).
- **Lifecycle**: `setup` / `enable` / `disable` / `toggle` / `is_installed`. `toggle()` flips `vim.g.beast_autopairs_disable` (cheap — actions short-circuit, no remap). Per-buffer opt-out via `vim.b.beast_autopairs_disable`.
- **Loaded via**: `packer.lazy("beast.libs.autopairs", { event = InsertEnter, keys = { <leader>up } })`.
- **Health**: `:checkhealth beast.libs.autopairs` reports API contract, mapping presence, and config dump.

Remove the same-day `mini.pairs` plugin entry from `lua/beast/plugins/init.lua`.

## Alternatives Considered

1. **Keep `mini.pairs` + the inline monkey-patch (the morning's decision).** ~60 LOC in `plugins/init.lua`, zero new lib. *Rejected after trial* because (a) the wrapper monkey-patches `pairs.open` — fragile against upstream changes to `mini.pairs`' internal call site; (b) leaving the engine as a black box meant we couldn't see/diagnose its behavior from `:checkhealth`; (c) the patch was already drifting toward the shape of an in-house lib (composing multiple veto rules in a deliberate order, handling cmdline differently) — at which point shipping a real lib is cleaner than a patch on someone else's module.
2. **Wrap `mini.pairs` as `lua/beast/libs/autopairs/` (a "lib that is a thin shim").** Owns the public surface but leaves the engine external. Rejected — adds a layer without removing the dependency, and we'd still be vulnerable to upstream API drift.
3. **`nvim-autopairs`.** ~3000 LOC, treesitter-rule DSL, completion-engine integration. Rejected — the integration surface (completion coordination, fast-wrap, multi-char pairs, filetype rules) is exactly the bloat we don't need given (a) blink.cmp's `accept = { auto_brackets = { enabled = false } }` removes the only coordination point, and (b) BeastVim doesn't use the fast-wrap or rule-DSL features.
4. **Do nothing.** Leave BeastVim without autopairs. Rejected — typing `(` should produce `()` in 2026; the absence is conspicuous.
5. **Vendor `mini.pairs`' source into the repo.** Removes the dependency at the cost of owning unfamiliar code styled differently from the rest of `beast/libs/`. Rejected — easier to write our own ~600 LOC against existing conventions (frozen config metatable, state-in-init, `Key.safe_set`, `Beast.View` siblings) than to maintain a foreign style island.

## Rationale

1. **The slice is small and the engine is well-understood.** ~250 LOC engine + ~140 LOC skip rules + ~120 LOC tests' supporting infra. Total committed lib + tests = ~1370 LOC across three phases. Below the threshold where "just take the plugin" pays off.
2. **Precedent.** Five prior ADRs (009, 018, 022, 025, 029) replaced external plugins with focused in-house libs covering only the slice BeastVim uses. Autopairs fits the pattern: a single integration point (`open` action) with composable pure-function vetoes in front.
3. **Testability.** All engine modules (`pairs.lua`, `actions.lua`, `skip.lua`) are pure or near-pure. 53 + 28 = 81 unit tests run headless in <1 s, exercising every pair shape, every veto rule, every disable-flag interaction, and the keymap install/uninstall roundtrip. Equivalent coverage against `mini.pairs` would require mocking its internals.
4. **No completion-engine coordination needed.** BeastVim's blink.cmp config has `auto_brackets.enabled = false`, so autopairs and completion don't fight over `(` post-acceptance. This removed the single hardest part of the "build vs adopt" calculation.
5. **`<expr>` mapping contract preserves Vim semantics.** Actions return keystroke strings; Neovim replays them through its normal input pipeline. Dot-repeat, undo, macros all work for free — same property `mini.pairs` has.

## Consequences

- **Positive:** Zero plugin dependency for autopairs. `:checkhealth beast.libs.autopairs` reports the lib's own state — no `mini.pairs` version skew to chase.
- **Positive:** Skip rules are pure functions with explicit signatures (`should_skip(cfg, ctx) → boolean, string?`) — adding a new veto is a one-function change, not a monkey-patch.
- **Positive:** Per-buffer disable (`vim.b.beast_autopairs_disable`) is a single-table lookup at action time — cheap toggling without unmap/remap cycles.
- **Positive:** Codemap (`docs/CODEMAPS/libraries.md`) gains a real "autopairs" section instead of a vague "mini.pairs is installed" footnote.
- **Negative:** We now own the engine forever — bug reports about brackets-don't-pair-here-but-should are ours to fix, not upstream's.
- **Negative:** Same-day reversal cost us one hour of work (the `mini.pairs` plugin entry + wrapper) that is now reverted. Cheap lesson; informs the size-threshold heuristic for future "wrap vs build" calls.
- **Risk:** `<expr>` mapping over `<CR>` collides with `blink.cmp`'s `<CR>` accept binding (last-registered wins). Mitigated today by load order — `blink.cmp` is heavier and lazier; if a collision shows up in real use, the fix is to have the autopairs `<CR>` consult `vim.fn.maparg("<CR>", "i")` and fall through.
- **Risk:** `vim.treesitter.get_captures_at_pos` errors on buffers without an active parser. Mitigated with `pcall`; unit-tested.
- **Future work (out of scope here):** fast-wrap, hunk-style multi-char pairs (`/* */`, ` <% %> `), filetype-specific pair sets (e.g. enable `<>` only inside JSX). Each is a follow-up dev spec; the current API leaves room.

## Reversal Note

This ADR explicitly reverses the same-day informal decision to use `mini.pairs`. The plugin entry never landed in a commit on `main` — it sat in the working tree for ~3 hours before being removed in `ad11759`. There is no prior ADR for the `mini.pairs` adoption (it was a working-tree experiment); this ADR is the first and only formal record of the autopairs decision.
