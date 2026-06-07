# ADR-029: BeastVim-Native LSP Infrastructure over `vim.lsp.config` / `vim.lsp.enable`

**Status:** Accepted

**Date:** 2026-06-08

**Evidence:** `lua/beast/libs/lsp/init.lua`, `lua/beast/libs/lsp/attach.lua`, `lua/beast/libs/lsp/capabilities.lua`, `lua/beast/libs/lsp/diagnostics.lua`, `lua/beast/libs/lsp/keys.lua`, `lua/beast/libs/lsp/config.lua`, `lua/beast/init.lua` (eager `Lsp.setup`), `lua/beast/setup/globals.lua` (`_G.Lsp`); dev spec `docs/dev-specs/lsp-library.md` § *Architecture*, § *Risks & Mitigations*; legacy reference: `~/.config/nvim/lua/beastvim/plugins/lang/*` (lazy.nvim opts-merging on `mason.nvim` + `nvim-lspconfig`); related: ADR-022 (native git lib), ADR-025 (native key popup).

## Context

Neovim 0.11 promoted `vim.lsp.config(name, cfg)` and `vim.lsp.enable(name)` to stable API. These two functions plus `vim.diagnostic.config` cover what BeastVim needs from an LSP layer: declare a server, enable it, configure diagnostics. The legacy distro (`~/.config/nvim/lua/beastvim/plugins/lang/*`) layered three plugins on top of this — `neovim/nvim-lspconfig` (server preset registry), `williamboman/mason.nvim` (binary installer), `williamboman/mason-lspconfig.nvim` (bridge) — bound together by `lazy.nvim` opts-merging across `~/.config/nvim/lua/beastvim/plugins/lang/*.lua` files.

Two pressures forced a redesign:

1. **API duplication.** `nvim-lspconfig` was originally a polyfill for what `vim.lsp.config` now ships natively. Keeping it means maintaining two ways to declare a server (`require("lspconfig").lua_ls.setup{}` vs `vim.lsp.config("lua_ls", {})`) and one extra plugin in the dependency graph for zero new capability.
2. **Ownership split.** The dev spec calls for per-language profiles to live in external `BeastVim/<Lang>` repos (see ADR-030), each calling `Lsp.register(name, cfg)`. That registration API has to be ours — passing through to `vim.lsp.config` directly leaves no seam for BeastVim extensions (`keys`, `on_attach`, capability contributors).

## Decision

1. **Build `beast.libs.lsp` directly on `vim.lsp.config` + `vim.lsp.enable` + `vim.diagnostic.config`.** No `nvim-lspconfig`, no `mason-lspconfig`. The lib's surface is `setup`, `register(name, cfg)`, `capabilities()`, `add_capabilities(contrib)`, `on_attach(fn)`.
2. **Own three pieces of infra and nothing else**: diagnostics defaults (`diagnostics.lua`), base capabilities + contributor merge (`capabilities.lua`), and a single `LspAttach` dispatcher (`attach.lua`).
3. **Do not wrap `vim.lsp.buf.*`.** No `Util.lsp.execute` / `Util.lsp.action` style helpers. Callers use native APIs directly; the lib only exposes what native APIs cannot do (capability merging, per-server gated keymaps via `client:supports_method`).
4. **Load eagerly from `beast/init.lua`**, not lazily on `FileType`. The lib must register `vim.lsp.enable()` calls before the first `FileType` autocmd fires, and any downstream `Lsp.register()` would force-load it anyway. Spec's lazy-load goal was a non-starter once that ordering was traced.

## Alternatives Considered

1. **Keep `nvim-lspconfig` + `mason.nvim` + `mason-lspconfig`.** The status quo. Rejected — every server preset in `nvim-lspconfig` is now a 5-line `vim.lsp.config` call; the registry no longer pays its plugin-dependency cost. Mason stays for binary installation (separate concern, separate ADR), but the lspconfig bridge has nothing left to bridge.
2. **Build a thin facade over `vim.lsp.buf.*`** (`Util.lsp.execute`, `Util.lsp.action`). User explicitly rejected this — "those are allowed to repeat vim.lsp.buf_request, I don't to override one layer over vim.lsp api". Wrapping native code only to rename it is anti-leverage.
3. **Lazy-load the lib on `FileType`** (per original spec Step 7). Rejected once the ordering trap surfaced — `vim.lsp.enable` must run before the matching `FileType` autocmd, and lang extensions calling `Lsp.register()` defeat the lazy-load anyway. Eager `Lsp.setup({})` from `beast/init.lua` is honest about the cost (a single `require` + `vim.diagnostic.config` + `nvim_create_augroup`, all O(constant)).
4. **Skip the dispatcher and let each consumer create its own `LspAttach` autocmd.** Rejected — diverges from the codebase's "one augroup per concern" convention (`lua/beast/util/root.lua:367` is the parallel example). A single `BeastVim-lsp` augroup with three ordered dispatch steps (per-server keys → per-server on_attach → global subscribers) is easier to reason about than N anonymous autocmds firing in load order.

## Rationale

1. **Native API is the contract.** Building on `vim.lsp.config` means the contract is documented by `:help vim.lsp.config` and version-tracked by Neovim core. Every plugin we drop is one less version-skew risk.
2. **Infra-only scope keeps the seam clean.** By owning *only* diagnostics + capabilities + dispatch, the lib has no per-language opinions to outdate. Lang extensions own those. See ADR-030 for that split.
3. **Eager load is honest.** The cost is bounded and constant. The alternative (lazy + force-load on first `register`) makes startup non-deterministic — the first language file opened pays a different cost than the second. Eager pays it once at startup, predictably.
4. **Single dispatcher = single ordering.** Per-server `keys` bind before per-server `on_attach` runs, which runs before global subscribers. Reasoning order is the file order in `attach.lua`. No load-order surprises.
5. **`_G.Lsp` mirrors the global convention** — `Util`, `Key`, `View`, `Palette`, `Icon`, `Lsp`. Adopting the name now (vs `Beast.lsp`) keeps lang extensions writing `Lsp.register(...)`, not the longer form.

## Consequences

- **Positive:** Three plugins removed from the dependency graph (`nvim-lspconfig`, `mason-lspconfig`, the bridge layer). One source of truth for "how do I declare a server" (`Lsp.register`). No translation layer between BeastVim's API and `vim.lsp.config` — the cfg table passes through after `keys`/`on_attach` are split out.
- **Positive:** The dispatcher's ordering is enforced by the file, not by registration order in user code. New global subscribers always run last; per-server hooks always run first.
- **Negative:** BeastVim now owns the equivalent of `nvim-lspconfig`'s preset registry — except we don't, because lang extensions do (ADR-030). The risk is that without external repos populated, the lib looks empty. Phase 2's `:BeastLspInfo` + `:checkhealth beast.libs.lsp` flag this honestly ("No servers registered yet").
- **Negative:** Capabilities are snapshotted at `register()` call time. A contributor `Lsp.add_capabilities(...)` added later won't apply retroactively to already-registered servers. Acceptable for the current loading order (capabilities → register → enable), but must be documented when blink.cmp wiring lands.
- **Neutral:** Eager `Lsp.setup({})` adds a fixed ~constant cost at startup. `bench-startup.sh` should be re-run when the lib has real consumers; the cost is currently below noise.
