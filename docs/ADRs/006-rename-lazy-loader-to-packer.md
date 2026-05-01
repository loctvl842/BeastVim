# ADR-006: Rename lazy_loader to packer

**Status:** Accepted

**Date:** 2026-04-26

**Evidence:** Commit `cdf5c01`; directory rename `lua/beast/libs/lazy_loader/` → `lua/beast/libs/packer/`

## Context

The plugin loader library was originally named `lazy_loader`. This created confusion because "lazy" in the codebase also refers to the lazy-loading *feature* (deferred plugin loading by event/key/module). The library name conflated the mechanism with the feature concept.

## Decision

Rename the library from `lazy_loader` to `packer`. Update directory paths, module `require()` paths, and type names (`Beast.LazyLoader.*` → `Beast.Packer.*`). Preserve field names that refer to the lazy-loading *feature* (`spec.lazy`, `lazy_plugins`, `lazy_specs`).

## Alternatives Considered

No alternatives documented in available evidence. Add if known.

## Rationale

1. "Packer" describes what the library *is* (a plugin packager/loader) without implying it only does lazy loading
2. Lazy-loading is one feature of the packer, not its identity
3. Clean separation of terminology: "packer" = the library, "lazy" = the deferred-load feature

## Consequences

- **Positive:** Clearer mental model; type names no longer ambiguous
- **Negative:** One-time churn on all require paths and type annotations
- **Risks:** External references (if any) to the old path break

## References

- Commit: `cdf5c01` — refactor: rename lazy_loader to packer
