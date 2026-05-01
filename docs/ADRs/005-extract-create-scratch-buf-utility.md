# ADR-005: Extract create_scratch_buf Utility

**Status:** Accepted

**Date:** 2026-04-25

**Evidence:** Commit `52d9786`; files modified in confirm, explorer, key, notify, toast

## Context

Five libraries (confirm, explorer, key, notify, toast) each contained identical scratch buffer creation code — setting `buftype=nofile`, `bufhidden=wipe`, `swapfile=false`, and a filetype. This duplication was tracked as a known DRY opportunity in the project conventions.

## Decision

Extract `create_scratch_buf(filetype)` into `Util.create_scratch_buf` in the shared util module. All five libraries now call the shared function instead of duplicating the logic.

## Alternatives Considered

No alternatives documented in available evidence. Add if known.

## Rationale

1. Five instances of identical code across four libraries exceeded the extraction threshold
2. Centralizing ensures consistent buffer options (if a new option is needed, change once)
3. Follows the project's "extract on threshold" rule from conventions

## Consequences

- **Positive:** Single source of truth for scratch buffer creation; less code per library
- **Negative:** Libraries now depend on the util module for a basic operation
- **Risks:** Minimal — the function is trivial and unlikely to change in breaking ways

## References

- Commit: `52d9786` — Extract create_scratch_buf utility to Util module
- Files changed: `confirm/ui.lua`, `explorer/ui.lua`, `key/ui.lua`, `notify/ui.lua`, `toast/ui.lua`
