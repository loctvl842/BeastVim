# ADR-022: Native Git Library Replaces gitsigns.nvim

**Status:** Accepted

**Date:** 2026-06-01

**Evidence:** Dev spec `docs/dev-specs/git-library.md`; files under `lua/beast/libs/git/`; commits `e639279` (Phase 1), `9124a05` (Phase 2), `f4fafa5` (Phase 3); related: ADR-009 (native statusline), ADR-015 (native tabline), ADR-018 (native scroll), ADR-020 (statuscolumn signs without plugin deps).

## Context

BeastVim already replaces heirline (ADR-009/015) and neoscroll (ADR-018) with focused native libraries under `lua/beast/libs/`. The statuscolumn library (ADR-020) was intentionally built to detect gitsigns extmarks by namespace, *without* `require("gitsigns")` — but that left the git glyphs blank unless `gitsigns.nvim` was installed.

`gitsigns.nvim` ships ~4 000 LOC covering: per-line signs, hunk navigation, hunk preview, blame line, stage/unstage hunk, reset hunk, word diff, hunk text-objects, rename-following, `.git/HEAD` watcher, telescope integration, and a Lua API. BeastVim uses, on a typical day, the first three.

## Decision

Build `lua/beast/libs/git/` as a focused native replacement covering exactly three features: **per-line hunk signs**, **hunk navigation (`]c` / `[c`)**, and **hunk preview (`<leader>gp`)**. Drop `gitsigns.nvim` from the plugin manifest. Everything beyond those three features is explicitly out of scope and deferred to follow-up specs.

The library:
- Resolves the repo and base text via `git rev-parse` + `git show HEAD:<path>` (one process per buffer per `BufWritePost` / `FocusGained`).
- Computes hunks via `vim.text.diff` (ADR-023).
- Places extmarks under namespace `beast_git_signs` (ADR-024) which the statuscolumn classifier routes via a single-line pattern addition (`^beast_git_signs`).
- Debounces `TextChanged{,I}` ~200 ms; single-flight per buffer (running/dirty flags) to avoid overlapping jobs on edit storms.

## Alternatives Considered

1. **Keep `gitsigns.nvim` as a dependency.** Fully featured, well-maintained, and the de-facto standard. Rejected because (a) BeastVim's wider direction is to own the small surface it actually uses (ADR-009/015/018), (b) gitsigns' Lua API has had breaking changes between majors that statuscolumn would have to chase, and (c) lazy-loading gitsigns specifically for sign extmarks pulls in the entire feature set we don't use.
2. **`mini.diff`.** Lighter than gitsigns and already pattern-matched by the statuscolumn classifier. Rejected because we'd still be importing an external plugin for a surface (`vim.text.diff` + `git show`) that we can author in ~500 LOC ourselves, and `mini.diff` doesn't ship hunk preview in the shape we want (a `View`-subclassed float consistent with notify/toast/confirm).
3. **A thinner shim over `gitsigns.nvim`'s Lua API.** Keeps the dependency but isolates the call sites. Rejected — adds a layer without removing the dependency, and the shim would still break on every gitsigns major.
4. **Port a port — vendor the relevant gitsigns subset.** Pulls in unfamiliar code we'd then have to maintain. Rejected — easier to write the ~500 LOC against our own conventions (frozen config, `Beast.View`, `beast.libs.packer.lazy`).

## Rationale

1. **Match BeastVim's "port the design, not the plugin" precedent.** Three libraries (statusline, tabline, scroll) have already replaced upstream plugins by porting only the slice the project uses. Git is the natural next candidate.
2. **The slice is small.** Per-line signs + nav + preview is ~500 LOC including the bench script. gitsigns is ~4 000 LOC. The 8× ratio reflects features we don't use, not features we'd lose.
3. **Statuscolumn integration falls out for free.** The classifier already routes by namespace; we add one pattern (`^beast_git_signs`) and our extmarks flow through the existing pipeline (ADR-020).
4. **Performance budget is achievable.** `vim.text.diff` is the same engine gitsigns delegates to internally — there is no realistic perf gap. Bench confirms: 5k lines = 2.6 ms (threshold 10 ms).
5. **Drops one runtime dependency** that previously had to be lazy-loaded, configured, and version-gated.

## Consequences

- **Positive:** Zero plugin dependency for git status display. `:checkhealth` reports BeastVim's own diff backend and attached state — no gitsigns version skew to chase.
- **Positive:** Hunk preview reuses `Beast.View` and matches the visual language of notify/toast/confirm/explorer floats. gitsigns' preview window is a stylistically separate citizen in the UI.
- **Positive:** Single-flight per buffer + 200 ms debounce keeps edit-storm cost predictable; bench 5k=2.6 ms < 10 ms threshold.
- **Negative:** We lose blame, staging, word diff, hunk text-objects, reset hunk, rename-following, `.git/HEAD` watcher. Each is recoverable in a follow-up spec, but they aren't free.
- **Negative:** Newly-tracked files (no HEAD object) render every line as `add` — matches gitsigns behaviour but worth knowing.
- **Risk:** External `git commit` outside Neovim doesn't reach us until `FocusGained` re-fetches the base. Acceptable: we explicitly chose this over a `.git/HEAD` filesystem watcher to keep the surface small. Mitigated by the universal `FocusGained` re-fetch path.
- **Risk:** EOL handling — `git show` emits trailing `\n` but `nvim_buf_get_lines + concat` doesn't. Caught during Phase 2 smoke testing; fixed by appending `\n` to the current text before diffing.
