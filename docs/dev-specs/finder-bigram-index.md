# Dev Spec: Finder Bigram Index — Persistent Prefilter for live_grep

## Summary

Build a persistent, in-process bigram inverted index in pure Lua/LuaJIT-FFI so
`live_grep` stops re-walking + re-reading the whole repo on the first keystroke.
At startup (lazily, on first grep) the engine scans every file once and records,
per file, which 2-byte sequences it contains in a bitset matrix (~56 MB for 90k
files). Each query ANDs the relevant bigram columns to a few-hundred candidate
files, then hands that file list to `rg` for verified matching. This complements
the existing incremental-narrowing cache in `source/live_grep.lua` (covers
keystroke #2+) by also collapsing keystroke #1 from "scan 90k" to "scan ~hundreds".

The key constraint vs fff's bigram: rg searches by **regex**, so bigrams are
extracted only from the query's **literal runs** (metacharacters like `(` `)` `.`
`*` are skipped); when no literal run ≥2 bytes exists, the prefilter is bypassed
and we fall back to a full `rg` scan — correctness is never sacrificed for speed.

## Requirements

- One-time content bigram index built on first `live_grep` open; build is
  backgrounded/chunked via `vim.uv` so the editor never blocks
- Query → bigram AND → candidate file list → `rg` verifies (no false negatives)
- Bigrams extracted only from literal runs of the (regex) query; non-literal or
  too-short queries fall back to full `rg` scan
- Survivors passed to `rg` as positional args; `xargs -0` fallback when survivors
  exceed a safe ARG_MAX threshold
- Index stays fresh: `fs_event` watcher reindexes changed files into a small
  overlay; deletes tombstone; no full rebuild on edit
- Memory bounded (~56 MB for ~90k files); files over a size cap are not indexed
  (searched directly, never dropped)
- Engine is opt-in via finder config; with it off, `live_grep` behaves exactly as today
- **Out of scope**: file/path fuzzy search (files source unchanged), regex HIR
  bigram extraction like fff, multi-threading/SIMD, frecency, MCP, replacing `rg`

## Research

### Repo Search
- Searched for: `git grep -niE 'live_grep|bigram|rg --json|ARG_MAX|fs_event|ffi'`
- Found:
  - `lua/beast/libs/finder/source/live_grep.lua` — spawns `ug`/`rg` per keystroke;
    already has incremental-narrowing cache + explicit-file args + `--json`/`%f` parsers
  - `lua/beast/libs/finder/pipeline/stream.lua` — stream pipeline driving live sources
  - `lua/beast/libs/finder/config.lua` — debounce/matcher config (add engine opts here)
  - FFI precedent: `lua/beast/libs/statuscolumn/ffi.lua`, `libs/image/dimensions.lua`
  - No existing content index, watcher, or grep bench (`scripts/bench-grep*` absent)
- Reuse opportunity: **Adopt** the explicit-file rg path + parsers in
  `live_grep.lua`; **Build** the bigram engine as a new `finder/engine/` module.

### Package Search
- Searched: native `vim.uv` (fs_scandir, fs_open/read, fs_event), LuaJIT `ffi`, `rg`/`xargs`
- Found: `vim.uv` covers async walk/read/watch; `ffi` covers fixed bitsets; `rg`
  takes a file list via args (verified) and `xargs -0` for unlimited sets (verified)
- Decision: **Build** on native + FFI; rg remains the verifier. No plugin.

## Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/libs/finder/engine/bigram.lua` | Create | FFI bitset matrix: `add(id,bytes)`, `query(literals)->ids`, key/AND |
| `lua/beast/libs/finder/engine/index.lua` | Create | Walk + chunked content scan + fs_event overlay; owns file list + bitsets |
| `lua/beast/libs/finder/engine/extract.lua` | Create | Literal-run bigram extraction from a regex query (skips metachars) |
| `lua/beast/libs/finder/source/live_grep.lua` | Modify | Use engine for prefilter; survivors→rg (args or xargs -0); off=current behavior |
| `lua/beast/libs/finder/config.lua` | Modify | `engine = { enabled, max_file_size, max_survivors }` |
| `scripts/bench-grep.lua` | Create | Bench index build + query AND on a target repo |
| `tests/test-bigram.lua` | Create | Unit tests: extract, AND, false-neg guarantee, fallback |

## Implementation Phases

### Phase 1: Bigram core + extraction — minimum viable, no integration
1. **`bigram.lua`** — FFI `uint64_t` columns (≤5000), `words=ceil(files/64)`; `add(id,bytes)`, `query(keys)->id list`. Risk: Med (FFI bounds).
2. **`extract.lua`** — split query into literal runs, drop metachars, emit bigram keys; empty if none ≥2. Why: rg-regex correctness. Risk: Med.
3. **`tests/test-bigram.lua` + `scripts/bench-grep.lua`** — AND correctness, extraction, false-neg guard; bench throughput. Risk: Low.

### Phase 2: Index builder — walk once, scan content, persist in RAM
1. **`index.lua`** walk via `rg --files` then chunked `uv` read+`add`, yielding per tick. Risk: High (build time).
2. Size cap: skip-but-track oversize files. Risk: Low.
3. `:checkhealth`-style stats (files, size, build ms). Risk: Low.

### Phase 3: Wire into live_grep behind config flag
1. Query→extract→AND→survivors→rg explicit files; >`max_survivors`→`xargs -0`. Risk: Med.
2. Fallback to today's path on empty bigrams/index-not-ready/flag-off. Risk: Low.

### Phase 4: Freshness — fs_event overlay
1. Watch root; overlay-bit changed files, tombstone deletes, OR overlay at query. Risk: Med.

## Testing Strategy
- Unit: `tests/test-bigram.lua` — extract metachars, AND, false-neg never, fallback.
- Bench: `scripts/bench-grep.lua` — build ms + avg survivors on the 90k repo.
- Manual: open grep on 90k repo; first keystroke fast; results identical to plain rg.

## Risks & Mitigations
- **Build too slow** → chunk via uv, lazy on first open, show progress; cap file size.
- **Survivor false negatives** → bigrams only prune; rg verifies; literal-only extraction.
- **RAM** → FFI bitsets capped ~56MB; size cap on indexable files.
- **Stale index** → fs_event overlay; full rebuild on cwd change.

## Success Criteria
- [ ] Build < 6s background on 90k/2.1GB; query AND < 5ms
- [ ] Results byte-identical to plain `rg` (no false negatives), incl. `(`,`)`,`.`
- [ ] `engine.enabled=false` = current behavior; `:checkhealth` clean
- [ ] Codemap regenerated and committed

## ADR Required
- New shared `finder/engine/` modules (index/bitsets) other code may require
- FFI bitset structure + fs_event index lifecycle
- Persistent index strategy: pure Lua + rg verify vs native binary
