# Daily Health Report — 2026-05-03 (evening)

Focused check requested by user: **statusline bench**.
Locks in the post-Phase 4 (opt-in result cache) baseline.

## 🟢 Run-time Render Performance

```
BENCH name=statusline beast=7.21us lualine=91.20us ratio=12.6x threshold=1000us
```

Exit `0` (PASS). Hard threshold 1 ms cleared by **~140×**; soft target
50 µs cleared by **~7×**. Variance across three back-to-back runs in the
same session: 6.10 µs / 6.41 µs / 7.21 µs — comfortably in the 6–8 µs band
predicted by the dev spec for Phase 4.

### Trend vs prior reports

| Report | beast µs/render | lualine µs/render | ratio | notes |
|---|---|---|---|---|
| `health-2026-05-03.md` | n/a | n/a | n/a | pre-bench-script |
| `health-2026-05-03-pm.md` (pre-Phase 4) | 14.37 | 90.51 | 6.3× | `git_commit` async refactor only |
| **this report (post-Phase 4)** | **7.21** | 91.20 | **12.6×** | opt-in result cache landed |

**Net improvement from Phase 4 alone:** ~50 % faster render, ratio doubled
from 6.3× → 12.6× faster than Lualine in the same setup.

The cause of the speedup is the new event-gated cache: components that
declare `update` (mode, position, filetype, shiftwidth, encoding,
diagnostics, git_branch, git_commit) now skip the provider on cache-hit
and only re-run on a declared event or BufWipeout / WinClosed cleanup.
Cheap providers that previously ran every keystroke (filetype string
format, shiftwidth lookup) are now amortised to ~zero on the steady-state
render path.

## 🟢 Other Signals (not re-checked this run)

The user's ask was scoped to the statusline bench. Other health signals
(startup time, codemap freshness, luacheck) were checked in
`health-2026-05-03-pm.md` and have not changed materially since — only
the statusline library was modified between reports.

## Action Items

None. Phase 4 lands cleanly within all thresholds and the trend is
strictly favourable.

### Watch for next report

- Whether the 6–8 µs band holds across full nvim startup (this bench uses
  `--clean`, so `BeastVim`-loaded statusline could be marginally
  different — worth a one-time cross-check at the next health report).
- Any new component added without `update` will show up as a per-render
  re-eval; track via `bench-statusline.lua` ratio drift over time.
