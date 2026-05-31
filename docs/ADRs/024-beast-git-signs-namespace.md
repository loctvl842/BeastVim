# ADR-024: Distinct `beast_git_signs` Namespace for Coexistence

**Status:** Accepted

**Date:** 2026-06-01

**Evidence:** `lua/beast/libs/git/signs.lua`; `lua/beast/libs/statuscolumn/signs.lua` (NS_PATTERNS table); dev spec `docs/dev-specs/git-library.md` § *Requirements*; related: ADR-020 (statuscolumn classifies signs by namespace).

## Context

The statuscolumn library (ADR-020) already classifies sign extmarks by namespace pattern. The existing patterns include `^gitsigns` for `gitsigns.nvim` and `^MiniDiff` for `mini.diff`. When our native git library places its own extmarks, the statuscolumn must route them to the `git` producer slot — but we *also* must support installs where the user keeps `gitsigns.nvim` around (e.g. for blame line) alongside BeastVim's native lib.

The trivial-looking option of reusing the `gitsigns` namespace name (so the existing `^gitsigns` pattern catches us automatically) would mean:
- Real `gitsigns.nvim` and our lib both place into the same namespace; deletions from one collide with the other.
- `:checkhealth gitsigns` would see our extmarks and lie about its own state.
- `nvim_get_namespaces()` returns a single id, hiding which side placed which sign.

## Decision

Place all sign extmarks under a dedicated namespace `beast_git_signs` (created once at module load via `nvim_create_namespace`). Prepend a new entry to the statuscolumn classifier's NS_PATTERNS table:

```lua
{ class = "git", pattern = "^beast_git_signs" },  -- routed first
{ class = "git", pattern = "^gitsigns" },          -- legacy / coexisting
```

Order matters only for clarity — both patterns route to the same `git` class — but listing ours first signals that our lib is the primary source when both are present.

## Alternatives Considered

1. **Reuse the `gitsigns` namespace name.** Zero statuscolumn change. Rejected — collision-by-design; deletions, health checks, and namespace ownership all become ambiguous.
2. **A pattern wildcard like `^.*gitsign`.** One pattern instead of two. Rejected — slower (regex backtracking), less explicit, and would silently catch any plugin that happens to contain "gitsign" in its namespace name.
3. **Reserve a `beast_*` namespace prefix convention** and rewrite the classifier to route any `^beast_` extmark with a sign type to a generic producer. Rejected for now — over-engineering for the second native lib that places signs (statuscolumn is the first via fold/number). Re-evaluate if a third such lib appears.
4. **No statuscolumn change; render signs ourselves into the gutter via `vim.fn.sign_place`.** Bypasses the statuscolumn pipeline entirely. Rejected — the whole point of the statuscolumn lib is single-source-of-truth for the gutter; double-rendering creates the exact slot-collision bug we built it to fix.

## Rationale

1. **One-line statuscolumn patch.** The `NS_PATTERNS` table is the seam ADR-020 designed for. Adding one entry is the smallest possible integration surface.
2. **Coexistence is real, not theoretical.** Users may install `gitsigns.nvim` for blame or stage-hunk while we provide the signs/nav/preview slice. Both libs placing into distinct namespaces means both can run without stepping on each other.
3. **Discoverable via `:checkhealth` and `nvim_get_namespaces`.** Operators can see exactly which extension owns which extmarks — the `beast_git_signs` name is searchable and self-describing.
4. **Survives a future statuscolumn re-architecture.** Even if the pattern table is replaced with a class-registration API, our namespace name is stable and self-attributing.

## Consequences

- **Positive:** Real `gitsigns.nvim` may be installed alongside us with no extmark collisions. The statuscolumn renders our signs (classifier matches `^beast_git_signs` first); gitsigns' own signs would *also* route to the `git` slot, with the last-placed sign winning per line — same behaviour as if a user installed two gitsign-style plugins.
- **Positive:** `nvim_buf_clear_namespace(buf, NS, 0, -1)` in `signs.place()` cleans up *only* our extmarks. We never touch gitsigns'.
- **Positive:** Statuscolumn change is a single 1-line patch — easy to revert if we ever drop the lib.
- **Negative:** Users with both plugins installed will see whichever lib placed last for any given line. Acceptable — running two sources of the same data is the user's choice. Documented in the dev spec's out-of-scope section.
- **Risk:** If a third plugin uses the literal namespace `beast_git_signs`, classification ambiguity. Vanishingly unlikely — the `beast_` prefix is project-specific.
