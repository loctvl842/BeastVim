# ADR-003: Read-Only Config Metatable Pattern

**Status:** Accepted

**Date:** 2026-04-24

**Evidence:** Commits `2557740`, `bb4a83c`; files `lua/beast/libs/key/config.lua`, `lua/beast/libs/notify/config.lua`

## Context

Libraries need a configuration system that separates defaults from live config, prevents accidental mutation of config state from outside the module, and supports hot-reloading via `setup(opts)`.

## Decision

Each library's `config.lua` uses a read-only metatable pattern:
- `defaults` table (never mutated)
- `cfg` (deep copy of defaults, merged with user opts on `setup()`)
- A metatable on `M` that exposes `cfg` fields via `__index` and raises errors on `__newindex`
- Methods table routed through the same metatable

## Alternatives Considered

No alternatives documented in available evidence. Add if known.

## Rationale

1. Prevents bugs from direct config mutation (`config.x = y` errors immediately)
2. `setup()` cleanly replaces the live config without stale references (other modules read `config.field` at call time)
3. Clean separation between config shape and behavior methods
4. Pattern proved stable in notify, then adopted by key and explorer

## Consequences

- **Positive:** Config bugs caught at assignment time; consistent API across libraries
- **Negative:** Slightly unusual Lua pattern — new contributors may not immediately understand the metatable indirection
- **Risks:** If `cfg` fields collide with method names, the method wins silently

## References

- Commit: `2557740` — key config extraction with readonly pattern
- Commit: `bb4a83c` — notify config already using this pattern (documented in codemaps)
- File: `lua/beast/libs/key/config.lua`
- File: `lua/beast/libs/notify/config.lua`
