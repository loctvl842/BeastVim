# ADR-002: Component-Based UI Architecture

**Status:** Accepted

**Date:** 2026-03-23

**Evidence:** Commits `510684e`, `7108ef8`, `91d8091`; directory structure `lua/beast/libs/`

## Context

The plugin needs multiple distinct UI features (file explorer, notifications, keybinding viewer, confirmation dialogs). Each has different rendering, keymaps, and lifecycle requirements.

## Decision

Organize the plugin as independent library components under `lua/beast/libs/`. Each library owns its own `init.lua` (public API + state), `config.lua` (defaults + setup), `ui.lua` (rendering), and optional submodules. Libraries communicate through the public API only — no cross-library internal imports.

Current libraries: `explorer`, `notify`, `key`, `confirm`, `toast`, `packer`.

## Alternatives Considered

No alternatives documented in available evidence. Add if known.

## Rationale

1. Each library can evolve independently without breaking others
2. Clear ownership of state (only `init.lua` holds mutable state)
3. New libraries follow a predictable structure — easy to scaffold
4. Dependencies only flow downward (config → ui → init), preventing cycles

## Consequences

- **Positive:** Adding new UI features is straightforward; isolation prevents regressions
- **Negative:** Some patterns repeat across libraries (addressed by DRY extractions over time)
- **Risks:** Without discipline, libraries may drift in conventions

## References

- Commit: `510684e` — explorer MVP (first multi-file library)
- Commit: `7108ef8` — notify init (second library, established pattern)
- Commit: `91d8091` — key UI init (third library, pattern solidified)
- Directory: `lua/beast/libs/`
