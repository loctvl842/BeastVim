# Finder levels refactor (2026-11)

The picker used to be one `State` that built the windows, the query and the pipeline together, with
behavior chosen by source name in five central files. It is now:

```
Session   windows, backdrop, keys, autocmds, picker opts, a stack of Levels      session.lua
Level     source + Query + engine + prompt text/title/count/cursor/offset        level.lua
Host      what an engine may ask of its owner (alive, render, busy, ...)         host.lua
Engine    pipeline/match.lua, pipeline/stream.lua: start/run/reload/abort/matches(query, host)
Source    get + format/header/group/open/preview_highlight/reload_on             source/*.lua
```

- A pipeline never touches windows. The Session gives each Level a host whose methods do nothing
  unless that level is the one shown, so a late answer of a replaced or popped level cannot draw.
- `match.matches(query)` returns the FULL set of matches (`query.matched` keeps only the best
  `query.limit`), nil while loading or scoring.
- A source declares its own row format, group header, Enter action and reload events. Nothing outside
  `source/init.lua` looks at a source name (a test enforces it).
- `Session:push(level)` / `pop()` show another level in the same windows; pop restores prompt, results,
  cursor and scroll without searching. Nothing binds a key to them yet.
- Keys: one action table and one binding table per pane in `keymaps.lua`.
- `search.lua` (headless, used by the explorer) runs the same match engine through `host.headless()`.

Spec: `docs/dev-specs/finder-levels-refactor.md`. Bugs the refactor's tests found and fixed: the match
loader busy-spun while a source was idle, the garbage collector it stopped was never restarted on abort,
a visibility change did not re-fetch an async source, a cleared live prompt left its spinner running,
a picker opened from `on_close` was closed again by the first picker's teardown, and a pattern typed
while loading could be overwritten by unscored arrivals.
