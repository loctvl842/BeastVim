# ADR-008: Namespaced Highlight Groups Across Libraries

**Status:** Accepted

**Date:** 2026-04-28

**Evidence:** Commits `57b0506`, `3c2f380`, `ea643b4`; `highlights.lua` files in explorer, confirm, key, packer

## Context

Libraries were defining highlight groups ad-hoc with inconsistent naming. This risked collisions with user highlights or other plugins, and made it hard to theme the plugin consistently.

## Decision

Standardize all highlight groups under the `Beast<Lib>*` namespace. Each library gets a dedicated `highlights.lua` file that defines its groups. All render code references these namespaced groups. A shared `Util.colors.set_hl` helper is used for consistent highlight application.

Examples: `BeastExplorerDir`, `BeastConfirmButton`, `BeastKeyBackdrop`, `BeastPackerSpinner`.

## Alternatives Considered

No alternatives documented in available evidence. Add if known.

## Rationale

1. Namespace prefix prevents collisions with user highlights or other plugins
2. Dedicated `highlights.lua` per library makes theming discoverable
3. `Util.colors.set_hl` ensures consistent defaults/linking across all libraries
4. Users can override any `Beast*` group in their colorscheme

## Consequences

- **Positive:** Zero collision risk; easy theming; discoverable highlight definitions
- **Negative:** More files per library; requires discipline to use the namespace
- **Risks:** If a library forgets the prefix, inconsistency creeps back

## References

- Commit: `57b0506` — feat(highlights): namespace all highlight groups across libs
- Commit: `3c2f380` — refactor(packer): standardize Util.colors.set_hl
- Commit: `ea643b4` — refactor(key): standardize key highlights
