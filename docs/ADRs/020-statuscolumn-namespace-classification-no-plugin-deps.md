# ADR-020: Statuscolumn Detects Signs by Namespace, No Plugin Dependencies

**Status:** Accepted

**Date:** 2026-05-31

**Evidence:** Dev spec `docs/dev-specs/statuscolumn-library.md`; file `lua/beast/libs/statuscolumn/signs.lua`; related: ADR-009 (`port the design, not the plugin`)

## Context

The statuscolumn library renders diagnostic and gitsign cells. The naive way to detect these is to `require("gitsigns")` and `vim.diagnostic.get(...)` per render. That couples the library to those plugins — but gitsigns is **not** in BeastVim's plugin manager (only referenced in the colorscheme palette), and the project has a long-standing convention (see ADR-009, ADR-015, ADR-018) of "port the design, not the plugin" — keeping libraries dependency-free so they degrade silently when an optional plugin isn't installed.

`snacks.nvim`'s statuscolumn detects git signs by matching `sign.name:lower():find("gitsign")` — a name-only heuristic that misses newer gitsigns versions where the extmark `sign_name` is empty and only `sign_hl_group` is populated.

`statuscol.nvim` solves this more robustly: it caches `nvim_get_namespaces()` and routes each extmark sign by both **namespace** (resolved from `ns_id`) **and** name/hl_group, with user-configurable allow/deny patterns per segment.

## Decision

Detect diagnostic and git signs **opportunistically**, by walking extmarks once per `(win, display_tick)` and classifying each by:

1. **Namespace pattern** (preferred) — resolve `extmark.details.ns_id` through a memoised `nvim_get_namespaces()` map and match against:
   - `^vim%.diagnostic` → class `diagnostic`
   - `^gitsigns` → class `git`
2. **Sign name / hl_group pattern** (fallback) — match against:
   - `^DiagnosticSign` / `^DiagnosticVirtualText` → class `diagnostic`
   - `^GitSigns` / `^MiniDiffSign` → class `git`
3. **Otherwise** → class `other` (not currently rendered; reserved for future producers).

The library **never** calls `require("gitsigns")`, `require("mini.diff")`, or `vim.diagnostic.get()` on the hot path. If gitsigns isn't installed, no extmarks match the git patterns and the git slot renders blank — silently, no error.

The `config.git.enabled = false` knob exists as a manual disable; even when enabled, missing plugins produce a no-op.

## Alternatives Considered

1. **`require("gitsigns")` + `gitsigns.get_hunks(buf)`.** Authoritative — gitsigns publishes a query API. Rejected — couples the lib to gitsigns being installed and to its API surface (which has had breaking changes between major versions). Violates ADR-009-style independence.

2. **`vim.diagnostic.get(buf)` per buffer per redraw.** Authoritative for diagnostics. Adds a per-redraw allocation (returns a fresh list table), and re-implements work the diagnostic framework already does when *placing* its extmarks. Rejected — extmark walk is one trip through one API; `vim.diagnostic.get` would be a second trip.

3. **Snacks-style `name:find("gitsign")` only, no namespace fallback.** Simple, but misses gitsigns versions where `sign_name` is nil and only `sign_hl_group` is set, and also misses any plugin that uses a namespace-only convention. Rejected — false negatives in real installs.

4. **User-configurable allow/deny patterns (statuscol-style).** Maximally flexible. Rejected for v1 as overkill — the default patterns cover gitsigns, mini.diff, vim.diagnostic, and the legacy `DiagnosticSign*` signs. If a user has an exotic source, they can override the producer behaviour via a future config knob; v1 keeps the patterns hardcoded in `signs.lua` so the perf budget is locked in.

## Rationale

1. **Decouples from the plugin lifecycle.** BeastVim's plugin manager (`packer`) lazy-loads; gitsigns may load *after* statuscolumn. A `require("gitsigns")` at setup time would error or pull in cold-start work. The namespace approach is event-time pull, not setup-time push.
2. **Survives plugin upgrades.** Plugin authors freely change sign names but rarely rename their extmark namespaces (because namespaces are part of the API surface for downstream consumers like our lib). The two-tier check (namespace first, name second) survives both classes of change.
3. **One extmark walk per redraw, amortised across all visible lines.** `nvim_buf_get_extmarks(buf, -1, 0, -1, { type = "sign", details = true })` runs once per `(win, display_tick)` and is bucketised into a `signs_by_lnum_by_class` table that all 80 visible-line evaluations share. Without this caching, each line would walk extmarks independently — the dev spec's per-line budget would be unreachable.
4. **Mirrors the precedent set by `scroll` (ADR-018) and `tabline` (ADR-015).** Both libraries are dependency-free implementations of features other plugins also provide. Statuscolumn extends the pattern.

## Consequences

- **Positive:** Works in any BeastVim install, whether gitsigns is present or not. No "if you don't have gitsigns, install this other plugin or comment out this slot" dance.
- **Positive:** A user who installs `mini.diff` or any future gitsign-equivalent automatically gets git glyphs in the column with zero config — the namespace + name patterns already cover the common alternatives.
- **Positive:** The namespace map cache (`ns_name_cache`) auto-refreshes on cache miss, so namespaces registered post-startup are picked up.
- **Negative:** The classifier hardcodes pattern strings. A new diagnostic-or-git source with a novel namespace would need a code change. Mitigated by the open-by-default `other` bucket and the easy one-line pattern addition.
- **Negative:** We don't get richer plugin data (e.g. gitsigns hunk type, diagnostic message) — only the rendered glyph and highlight. This is fine for a status column; the breadcrumb / diagnostics float handles the richer surfaces.
- **Risks:** If gitsigns ever ships with an extmark namespace that doesn't start with `gitsigns` AND a sign without a `GitSigns*` name, our classifier would silently miss them. Surfaced via `:checkhealth` (signs present in buffer but no class-matched producer) — a future enhancement.
