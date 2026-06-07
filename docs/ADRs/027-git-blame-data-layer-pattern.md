# ADR-027: Git Blame via `vim.system` + Buffered Porcelain Parse

**Status:** Accepted

**Date:** 2026-06-07

**Evidence:** `lua/beast/libs/git/blame.lua`; dev spec `docs/dev-specs/git-blame.md` § *Research*; `scripts/bench-git-blame.lua`; related: ADR-022 (native git lib over gitsigns.nvim), ADR-023 (vim.text.diff backend).

## Context

Adding git blame to `beast.libs.git` required choosing a runtime model for shelling out to `git blame --incremental` and consuming its porcelain output. The reference implementation in `gitsigns.nvim` uses a streaming model: a coroutine-based buffered line reader receives stdout chunks as they arrive, parses each commit block, and emits per-block results into gitsigns' async runtime — which then schedules incremental UI updates.

Our two consumers — current-line cursor blame and full-file blame side window — both wait for the full blame result before painting anything. Cursor blame paints one extmark for the line under the cursor; the side window renders the whole file in a single buffer write. Neither benefits from intermediate results.

Adopting the streaming model wholesale would require:
- A coroutine line reader handling partial-line splits at chunk boundaries.
- Block-by-block parser plumbing.
- An async runtime layer (we don't have one — gitsigns' own runtime is ~400 LOC).
- Or callback-juggling shims to map block emission onto our existing `vim.schedule`-callback shape.

## Decision

Use `vim.system(cmd, { text = true, stdin = ... }, on_exit)` and parse the entire stdout in one pass inside the `on_exit` callback. No streaming, no coroutines, no buffered line reader. The parser is a single function `M._parse(stdout)` that splits on `\n` and walks blocks sequentially via `parse_block(lines, i, commits, result)`.

Untracked-file fallback is handled in the wrapper before any subprocess spawn: when `opts.untracked = true`, we synthesize a "Not Committed Yet" commit covering the requested range and skip git entirely.

## Alternatives Considered

1. **Stream stdout via the `stdout = fn` chunk callback + coroutine line reader (gitsigns' shape).** Faithful to the upstream pattern. Rejected — adds ~80 LOC of coroutine/buffer plumbing for zero observable benefit. Neither cursor blame nor the side window can usefully act on partial blame results; both wait for the full table.
2. **Synchronous `vim.system(...):wait()`.** Simpler still (no async). Rejected — `:wait()` blocks the main loop; even ~40ms cursor blame on every CursorMoved would feel like jank.
3. **Shell out to `git log -L :func,/relpath` instead of `git blame`.** Better for "history of a function" UX. Rejected as scope creep — orthogonal to "who wrote this line" and twice the parsing surface.
4. **Use `libgit2` via a Lua FFI binding.** No subprocess, microsecond response. Rejected — adds a native dependency, breaks the ADR-022 "native, no plugins" stance for the wrong axis (we wanted "no Lua-plugin deps", not "no native deps"), and zero existing libfit2 wrapper in BeastVim to share the binding cost with.

## Rationale

1. **Smaller code, identical correctness.** The buffered parser is ~120 LOC including types and the untracked fallback. The streaming equivalent in gitsigns is ~210 LOC across `git/blame.lua` and the buffered_line_reader coroutine. We do the same job in roughly half.
2. **Single async hop matches the rest of the lib.** Every other repo wrapper in `lua/beast/libs/git/repo.lua` uses `vim.system(..., on_exit)` + `vim.schedule(cb)`. Blame fits the same shape with zero new primitives.
3. **Bench numbers prove streaming wouldn't help.** `scripts/bench-git-blame.lua` measures ~40ms median single-line and ~60ms median full-file (624-line fixture). Both are dominated by `vim.system → git` process startup (~40ms floor on macOS), not by parsing. Streaming optimizes the wrong half of the round-trip.
4. **Easy to swap if the workload changes.** The seam is a single function `M.run(ctx, opts, cb)`. If a future use case ever needs incremental results (e.g. blaming a 50k-line file with live updates), we can replace the body without changing any caller.

## Consequences

- **Positive:** Cursor blame and the side window share one tested code path. The parser is a pure function (`M._parse(stdout)` is exported) and easy to unit-test against fixture porcelain payloads.
- **Positive:** No coroutine machinery to debug; no partial-chunk edge cases at the parser layer (the splitter handles them via `vim.split` once).
- **Positive:** Stdin support for `--contents -` (so modified buffers blame against in-memory text) is one line — `stdin = table.concat(opts.contents, "\n")`.
- **Negative:** Full-file blame on a hypothetical 100k-line file would buffer ~10MB of stdout in memory before parsing. Acceptable — that's roughly 100x larger than any real file we'd open, and `vim.system` would not be the limit (the buffer holding the file in nvim would dwarf it).
- **Risk:** If git's porcelain format ever gains a tag we don't parse, we'd silently drop it. Mitigated by mirroring gitsigns' normalization for the known git-2.41 `<external.file>` marker and by an `error()` in `parse_block` for malformed headers (visible in :messages).
- **Risk:** A future "watch blame as you edit" feature would require incremental output. At that point we'd refactor `M.run` to optionally stream — the consumer surface stays the same.
