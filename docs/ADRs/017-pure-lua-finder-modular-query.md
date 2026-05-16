# ADR-017: Pure-Lua Finder with Modular Query Architecture

**Status:** Accepted

**Date:** 2026-05-17

**Evidence:** `lua/beast/libs/finder/query.lua` (Query class: layout, source loading, batch flush, rematch); `lua/beast/libs/finder/matcher.lua` (fzf boundary-bonus scoring); `lua/beast/libs/finder/source/init.lua` (lazy registry via `__index`); `lua/beast/libs/finder/ui/` (InputView, ListView, PreviewView — all subclass Beast.View); `lua/beast/libs/async.lua` (cooperative coroutine scheduler); commits `a0bc873` Phase 1, `218431c` Phase 2, `4c01e84` Phase 3, `6b877f1` rewrite to modular query; `docs/dev-specs/finder-library.md`

## Context

BeastVim had no built-in picker. External options (Telescope, fzf-lua, snacks.nvim picker) each add significant dependencies: Telescope requires plenary + telescope-fzf-native, fzf-lua requires the fzf binary + terminal buffer, snacks.nvim brings a large plugin surface. The project's direction (ADR-009, ADR-015) is to replace external plugins with focused native implementations. A fuzzy finder is the last major UI component that required an external plugin.

## Decision

Build `lua/beast/libs/finder/` as a pure-Lua fuzzy picker with no mandatory external binary. Architecture:

```
finder/
├── init.lua       ← open(source, opts), setup()
├── query.lua      ← Query class: orchestrates layout, sources, matching, rendering
├── matcher.lua    ← fzf boundary-bonus fuzzy scoring algorithm
├── filter.lua     ← Filter class: pattern + cwd state
├── source/        ← lazy-loaded source registry (__index → require)
│   ├── files.lua      (async: fd/rg/find via uv.spawn)
│   ├── buffers.lua    (sync: getbufinfo)
│   ├── live_grep.lua  (live async: rg with pattern)
│   ├── colorschemes.lua (sync: rtp-only)
│   └── help_tags.lua  (sync: rtp-only, loaded plugins only)
├── ui/            ← three View subclasses (input, list, preview) + backdrop
├── keymaps.lua    ← per-pane keymaps with printable-char redirect
├── action.lua     ← open, open_help, open_split, open_vsplit
└── format.lua     ← per-source display formatters (Highlight[] pipeline)
```

Key design choices:
- **Query owns the lifecycle** — layout geometry, source loading, batch flush, rematch, preview scheduling all live in one class.
- **Sources are lazy** — `source/init.lua` uses `__index` to require on first access. Adding a source means adding one file.
- **Async sources use `uv.spawn`** — file listing streams items via stdout pipe, batched into groups of 100 before triggering rematch.
- **Sources only scan loaded plugins** — `colorschemes` and `help_tags` use `vim.o.runtimepath` as-is, not injecting unloaded opt plugin paths.
- **Three View subclasses** — InputView (prompt buffer + debounced TextChanged), ListView (rendered items + cursor + prefix extmarks), PreviewView (file content + filetype detection). All extend `Beast.View` per ADR-001.

## Alternatives Considered

Dev spec (`finder-library.md`) documents the research:
- **snacks.nvim picker** — structured items and Filter/Matcher separation adopted; layout engine, MinHeap top-k, frecency persistence, per-picker autocmd forests deliberately rejected as over-complex.
- **fzf-lua** — terminal buffer + external binary + ANSI strings architecture explicitly not adopted; the goal is zero mandatory external binaries.
- **Telescope** — requires plenary.nvim + telescope-fzf-native C extension; heavier dependency surface than desired.

## Rationale

1. Follows the project direction of replacing external plugins with native implementations (ADR-009 statusline, ADR-015 tabline, now finder).
2. Zero mandatory external dependencies — `fd`/`rg` are optional performance accelerators, `find` is the fallback.
3. fzf boundary-bonus scoring gives quality results without a C extension (matcher.lua).
4. Modular query architecture (commit `6b877f1` rewrite) separates concerns cleanly: source loading, matching, rendering, and keymaps are independent files.
5. rtp-only source scanning (colorschemes, help_tags) prevents errors from unloaded opt plugins — discovered and fixed during implementation.

## Consequences

- **Positive:** No external plugin dependency for fuzzy finding. Sources are trivially extensible (one file per source). Three-pane layout (input/list/preview) with pane-local keymaps and printable-char redirect for seamless UX.
- **Negative:** Pure-Lua matcher will be slower than fzf-native or telescope-fzf-native on very large repos (>100k files). No frecency or history ranking.
- **Risks:** Async batch flush timing (100-item threshold) may feel sluggish on slow I/O. The `uv.spawn` → stdout pipe → batch → rematch chain is the path to audit if perceived latency increases.

## References

- Commits: `a0bc873` (Phase 1), `218431c` (Phase 2), `4c01e84` (Phase 3), `6b877f1` (modular rewrite)
- Dev spec: `docs/dev-specs/finder-library.md`
- Related ADRs: follows [ADR-001](001-view-base-class-for-buf-win-pairs.md) (View subclasses), [ADR-009](009-native-statusline-replaces-heirline.md) / [ADR-015](015-native-tabline-replaces-heirline.md) (native-over-plugin direction)
