# Architecture Decision Records — BeastVim

| ADR | Title | Status | Date |
|-----|-------|--------|------|
| [001](001-view-base-class-for-buf-win-pairs.md) | View Base Class for Buffer+Window Pairs | Accepted | 2026-03-23 |
| [002](002-component-based-ui-architecture.md) | Component-Based UI Architecture | Accepted | 2026-03-23 |
| [003](003-readonly-config-metatable-pattern.md) | Read-Only Config Metatable Pattern | Accepted | 2026-04-24 |
| [004](004-extract-shared-animate-module.md) | Extract Shared Animation Module | Accepted | 2026-04-21 |
| [005](005-extract-create-scratch-buf-utility.md) | Extract create_scratch_buf Utility | Accepted | 2026-04-25 |
| [006](006-rename-lazy-loader-to-packer.md) | Rename lazy_loader to packer | Accepted | 2026-04-26 |
| [007](007-confirm-as-vim-fn-confirm-drop-in.md) | Confirm UI as vim.fn.confirm Drop-In | Accepted | 2026-04-30 |
| [008](008-namespaced-highlight-groups.md) | Namespaced Highlight Groups Across Libs | Accepted | 2026-04-28 |
| [009](009-native-statusline-replaces-heirline.md) | Native `%!` Statusline Replaces Heirline | Accepted | 2026-05-02 |
| [010](010-no-engine-level-statusline-cache.md) | No Engine-Level Statusline Cache | Superseded by [013](013-opt-in-statusline-result-caching.md) | 2026-05-02 |
| [011](011-file-bound-provider-wrapper.md) | file_bound Provider Wrapper for Transient UI Buffers | Accepted | 2026-05-02 |
| [012](012-compound-fragment-component-model.md) | Compound-Fragment Component Model | Accepted | 2026-05-02 |
| [013](013-opt-in-statusline-result-caching.md) | Opt-In Result Caching with Event-Gated Invalidation | Accepted | 2026-05-03 |
| [014](014-child-float-over-split-parent-owned-lifecycle.md) | Child Float Overlaying a Split, Lifecycle Owned by Parent | Accepted | 2026-05-06 |
| [015](015-native-tabline-replaces-heirline.md) | Native `%!` Tabline Replaces Heirline | Accepted | 2026-05-11 |
| [016](016-tabline-3-state-highlights-event-cache.md) | Tabline 3-State Highlights with Event Cache | Accepted | 2026-05-11 |
| [017](017-pure-lua-finder-modular-query.md) | Pure-Lua Finder with Modular Query Architecture | Accepted | 2026-05-17 |
| [018](018-native-scroll-library-viewport-animation.md) | Native Smooth Scroll Library (Viewport Animation) | Accepted | 2026-05-28 |
| [019](019-statuscolumn-fixed-producer-enum.md) | Fixed Producer Enum for Statuscolumn (over Generic Segment Engine) | Accepted | 2026-05-31 |
| [020](020-statuscolumn-namespace-classification-no-plugin-deps.md) | Statuscolumn Detects Signs by Namespace, No Plugin Dependencies | Accepted | 2026-05-31 |
| [021](021-statuscolumn-display-tick-cache-invalidation.md) | `display_tick` (FFI) Drives Statuscolumn Cache Invalidation | Accepted | 2026-05-31 |
