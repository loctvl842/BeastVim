# ADR-009: Native `%!` Statusline Replaces Heirline

**Status:** Accepted

**Date:** 2026-05-02

**Evidence:** Dev spec `docs/dev-specs/statusline-library.md`; library at `lua/beast/libs/statusline/`; `vim.o.statusline = "%!v:lua.require'beast.libs.statusline'.render()"` in `init.lua`

## Context

The statusline component of `heirline.nvim` was the only piece of heirline we used non-trivially — its tabline and winbar are simpler. Heirline's recursive component tree, ancestry chains, and metatable inheritance added machinery that the BeastVim layout (~8 flat components in left/right regions) did not need. Owning the statusline rendering also unlocks tighter integration with other Beast libs (`Palette`, `M.highlight_modules`, `IGNORED_FILETYPES` for transient `beast-*` UI buffers).

## Decision

Build a native statusline library at `lua/beast/libs/statusline/` that uses Neovim's `%!` evaluation model directly. Set `vim.o.statusline` to a Lua expression that calls `render()` on every redraw. Heirline still drives the tabline and winbar.

Public API mirrors other Beast libs:

```lua
local stl = require("beast.libs.statusline")
stl.setup({
    left  = { cpn.git_branch, cpn.diagnostics },
    right = { cpn.git_commit, cpn.position, cpn.filetype, ... },
})
```

Components are declarative tables (`provider`, `condition`, `update`, `scope`, `priority`, `separator`) — heirline's spec shape, without the inheritance.

## Alternatives Considered

- **Keep heirline.nvim** — rejected: the recursive tree is overkill for ~8 flat components, and we want native `Palette` and `IGNORED_FILETYPES` integration.
- **Switch to lualine.nvim** — rejected: lualine sets `&statusline` directly and runs its own refresh timer; that fights Neovim's redraw logic, and the framework is heavier than what we need.
- **Build on top of `nvim_set_option_value("statusline", ...)`** — rejected in favor of `%!`: with `%!` Neovim decides when to redraw and calls our function; we don't need our own refresh loop.

## Rationale

1. `%!` lets Neovim handle redraw timing — no timer or coalescing logic in our code
2. Native items (`%l`, `%c`, `%P`) still pass through the returned string for free
3. `g:statusline_winid` gives us per-window context (active vs inactive) without guessing
4. Removes a third-party dependency from the statusline render path
5. Aligns the statusline with BeastVim conventions (state in `init.lua`, frozen-config metatable, `M.highlight_modules` registry)

## Consequences

- **Positive:** Render is cheap (`table.concat` + `vim.bo` reads); no third-party API to track; tighter integration with `Palette` / `IGNORED_FILETYPES`; easy to extend (new component = new file in `components/`)
- **Negative:** We own the render correctness — the `laststatus=3` width bug and toast-during-startup glitch were ours to find and fix; heirline already handled these
- **Risks:** If Neovim changes `%!` semantics or `g:statusline_winid` behavior, we need to adapt; tabline/winbar stay on heirline until similar libs are built

## References

- Dev spec: `docs/dev-specs/statusline-library.md`
- Library: `lua/beast/libs/statusline/`
- Related ADRs:
  - [ADR-002](002-component-based-ui-architecture.md) — Component-Based UI Architecture
  - [ADR-010](010-no-engine-level-statusline-cache.md) — No Engine-Level Statusline Cache
  - [ADR-011](011-file-bound-provider-wrapper.md) — file_bound Provider Wrapper
  - [ADR-012](012-compound-fragment-component-model.md) — Compound-Fragment Component Model
