# ADR-019: Fixed Producer Enum for Statuscolumn (over Generic Segment Engine)

**Status:** Accepted

**Date:** 2026-05-31

**Evidence:** Dev spec `docs/dev-specs/statuscolumn-library.md`; files `lua/beast/libs/statuscolumn/{init,config,fold,number,signs}.lua`

## Context

A new `lua/beast/libs/statuscolumn/` library renders Neovim's `'statuscolumn'` natively. The render fn (`%!v:lua.require'beast.libs.statuscolumn'.render()`) is evaluated **once per visible screen line per redraw** — for an 80-row window with `signcolumn=auto:2`, gitsigns, and diagnostics, that's hundreds of evaluations per keystroke. The hot-path budget set by the dev spec is **<5 µs / line median**.

Two reference implementations were studied:

- **`snacks.nvim`'s `statuscolumn.lua`** (~355 LOC) — fixed 3-slot layout (left/number/right). Producers (`mark`/`sign`/`fold`/`git`) are bound at compile time inside the render loop. Hard to extend, easy to optimise.
- **`statuscol.nvim`** (~600 LOC) — fully generic segment engine. Each segment is an opaque `{text=fn, click=fn, condition=fn, ...}` table iterated per line, with pattern arrays (`text/notext/namespace/notnamespace/name/notname`) for sign routing. Extensible to user-defined segments, but each line goes through an array of function pointers and pattern lists.

We needed a layout that:

1. Lets the user position cells (left-to-right) and route which signs render in which cell (statuscol's main strength).
2. Keeps the per-line dispatch cost flat — no per-line function-table iteration.
3. Has zero plugin dependency — gitsigns/mini.diff/vim.diagnostic detected by extmark namespace + name pattern.

## Decision

Implement statuscolumn with a **fixed closed enum of producers** (`number | diagnostic | git | fold`) and a **slot-based layout** the user composes:

```lua
segments = {
  { "diagnostic" },         -- slot 1
  { "number" },             -- slot 2
  { "git" },                -- slot 3
  { "diagnostic", "fold" }, -- slot 4 — first producer with output wins
}
```

Each entry in `segments` is one rendered cell. Each cell is an ordered priority list of producer names. At render time, the per-slot resolver walks the list and picks the first producer that has output for the current line; the rest are short-circuited.

Producers live in a `local producers = { number=..., diagnostic=..., git=..., fold=... }` table inside `init.lua`. Dispatch is `producers[slot[i]](win, buf, lnum, ...)` — a single hash lookup per producer per slot, no array of opaque function pointers.

The producer enum is **closed**. There is no public API to register a new producer at runtime; adding one requires editing `init.lua`. Validity is enforced in `health.lua` (`VALID_PRODUCERS`).

## Alternatives Considered

1. **Adopt `statuscol.nvim`'s generic segment engine verbatim.** Most flexible (users could write `{ text = my_fn, sign = { namespace = {...} } }`), but per-line cost includes iterating an array of opaque segments and walking pattern arrays per segment. Rejected — flexibility we don't need at a cost we can't ignore on a per-screen-line hot path.

2. **Adopt `snacks.nvim`'s fixed left/number/right layout.** Simple and fast, but the user can't choose ordering (number is always centred) and can't share a cell across producers (no slot-priority semantics). Rejected — loses statuscol's main UX strength.

3. **Hybrid: fixed enum, but allow `slot = { producer_table }` with custom `render` fn per slot.** Lets advanced users embed custom producers per slot. Rejected — opens the door to per-line user code, which makes the perf contract un-enforceable in tests and `:checkhealth`. The dev spec marks this as explicitly out of scope.

## Rationale

1. **Dispatch cost is O(1) per producer per slot.** A 4-slot layout dispatching 1 producer each is 4 hash lookups + 4 function calls; statuscol's segment-array model adds an outer iteration plus pattern arrays per segment. The 5 µs/line budget assumes the cheaper model.
2. **Slot-priority semantics carry over from statuscol.** The user can still do `{"diagnostic","fold"}` to share a cell — the *user* composes producers into slots; the *library* enforces the producer set.
3. **Closed enum means typo-safe and bench-safe.** `health.lua` validates every slot entry against `VALID_PRODUCERS`. The bench script knows the producer set up front and can exercise each producer in isolation. A generic engine would have to bench user-supplied callbacks, which is meaningless.
4. **Fixed enum doesn't preclude future expansion.** Adding `mark` is one entry in the enum and one producer fn. The `dev spec`'s "Out of Scope" explicitly notes that mark + dap could be added later via the same mechanism — no API break.

## Consequences

- **Positive:** Per-line dispatch is a hash lookup + a function call — no array walk, no pattern matching at dispatch time. Bench measures `3.3 µs/line` for the full 4-segment layout with seeded signs (well under the 5 µs threshold).
- **Positive:** `:checkhealth` can authoritatively validate every slot entry against the enum and surface typos at startup.
- **Positive:** The producer code is self-contained and locally testable (e.g. `number.format(win, lnum, relnum, virtnum)` is a pure function).
- **Negative:** Users cannot add a custom producer (e.g. "show a glyph next to lines covered by a test run") without forking the library. This is a deliberate trade-off — the lib targets the four producers it knows how to make fast, not arbitrary user code on the hot path.
- **Negative:** The library does *not* port statuscol's full feature set (sclnu, scfa, foldfunc, sign click handlers, click_args dispatch). These are out of scope by the same simplification.
- **Risks:** A user who wants a fifth producer either submits a PR (small change — add to producers table + spec entry) or wraps the rendered string post-hoc. No upstream extension API to break.
