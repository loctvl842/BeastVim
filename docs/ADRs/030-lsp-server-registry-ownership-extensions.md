# ADR-030: LSP Server Registry Ownership — Extensions Own Per-Language Configs

**Status:** Accepted

**Date:** 2026-06-08

**Evidence:** `lua/beast/libs/lsp/init.lua` (`Lsp.register` API surface); `lua/beast/libs/treesitter/init.lua` (sibling "infra-only" precedent); dev spec `docs/dev-specs/lsp-library.md` § *Out of Scope* ("server registry, per-language presets, mason integration"); planned external repos under `https://github.com/BeastVim/<Lang>`; related: ADR-029 (native LSP infra).

## Context

The legacy distro (`~/.config/nvim/lua/beastvim/plugins/lang/*.lua`) kept per-language LSP/treesitter/formatter/keymap config inline in BeastVim. Each new language meant a new file in the BeastVim repo. This made the distro grow linearly with the number of supported languages — most of which any given user never touches.

The Zed model is different: a Lua file opens, a popup asks "install Lua extension?", and the language extension brings its own LSP server name, root markers, treesitter parser list, and formatter config. The distro itself stays language-agnostic.

The `lsp` library was designed to support that model. The decision is *who owns the per-server cfg table*.

## Decision

1. **`beast.libs.lsp` owns no per-server knowledge.** Zero entries in the lib for `lua_ls`, `pyright`, `tsserver`, etc. The lib's job is the registration mechanism + the dispatcher + the capabilities pipeline.
2. **Per-language configs live in external `BeastVim/<Lang>` repos** (e.g. `BeastVim/Lua`, `BeastVim/Python`, `BeastVim/TypeScript`). Each repo exports a single Lua module with shape `{ meta, deps?, setup(ctx) }`. The `setup(ctx)` function is the call site for `Lsp.register("lua_ls", { ... })`, `Treesitter.ensure({...})`, formatter wiring, and any language-specific keymaps.
3. **Install via `vim.pack`**, not via a custom extension manager. `vim.pack.add({ "https://github.com/BeastVim/Lua" })` matches the BeastVim convention used for every other plugin — extensions are just plugins with a stricter shape.
4. **The seam is the cfg passed to `Lsp.register(name, cfg)`.** It accepts a `vim.lsp.Config` table augmented with `keys` and `on_attach` (see ADR-031 for that contract). Anything else the lang extension wants is the lang extension's own problem — `setup(ctx)` can do whatever Lua can do.

## Alternatives Considered

1. **Keep per-language files in the BeastVim repo** (`lua/beast/lang/<name>.lua`). The legacy model. Rejected — couples distro size to language count; users carry config for languages they never touch; a TypeScript-only user is paying for every Lua/Rust/Go preset that ships in the box.
2. **Build a registry inside `beast.libs.lsp`** with `Lsp.preset("lua_ls")` returning a canned config. Rejected — that's `nvim-lspconfig` rebuilt inside our lib. Same maintenance burden, same staleness risk, no leverage gained.
3. **Build a separate extension manager lib** (`beast.libs.extensions`) with manifest discovery, dependency resolution, a prompt UX. User explicitly rejected this — "we have vim.pack already and more important is this is used for lsp+treesitter only". The extension manager would be one wrapper over `vim.pack` plus a popup. Not enough leverage to justify a new lib.
4. **Inline configs in user `lua/config/lang/` files**, no external repos at all. Rejected — the goal is shareability. A `BeastVim/Lua` repo means the *community* writes the Lua preset once, and every BeastVim user benefits. A user's local `lang/lua.lua` benefits one person.
5. **Mason for both binary install and config registry.** Rejected — mason is a binary installer. Conflating "install the binary" with "configure the server" is the failure mode that made `mason-lspconfig` necessary in the first place. Keep them separate; future "binary install" ADR will pick a tool.

## Rationale

1. **The lib stays small.** `beast.libs.lsp` is six files and ~250 lines because it has nothing language-specific to host. Lines that aren't there can't break.
2. **Distro size decouples from language count.** Adding Rust support is `vim.pack.add("BeastVim/Rust")`, not a PR to BeastVim. The distro grows linearly in capability, not in language coverage.
3. **The `setup(ctx)` contract is escape-hatched by design.** Different languages have different needs (TypeScript wants `tsserver` + ESLint + Prettier wiring; Lua wants `lua_ls` + workspace library discovery; Go wants `gopls` + dap). One JSON manifest can't express all of that. A Lua function can.
4. **`vim.pack` is the existing convention.** Every plugin in BeastVim is loaded via `vim.pack`. Extensions go through the same code path — no parallel install mechanism, no parallel update mechanism, no parallel `:checkhealth`.
5. **Matches the treesitter sibling.** `beast.libs.treesitter` owns parse/highlight infra; the parser list is the consumer's problem. The lsp lib mirrors that exactly — own setup, not the registry.

## Consequences

- **Positive:** New language support requires zero BeastVim PRs. A user can publish `BeastVim/Crystal` and other users `vim.pack.add` it immediately.
- **Positive:** Each `BeastVim/<Lang>` repo can move at its own pace — Lua extension stays stable while Python extension iterates on pyright vs basedpyright vs ty.
- **Positive:** Out-of-box BeastVim has no LSP servers configured, which makes the "what does this distro give me" answer honest. `:BeastLspInfo` shows "No servers registered" until extensions are installed.
- **Negative:** First-run UX is rough until at least one extension is published. Until `BeastVim/Lua` exists, opening a Lua file in BeastVim does nothing LSP-wise. Mitigated by Phase 2's discoverability (`:BeastLspInfo`) and a future onboarding ADR that may seed defaults.
- **Negative:** The `setup(ctx)` Lua-function contract is more powerful than a declarative manifest, which means it's also harder to validate statically. A buggy extension can break the load cycle. Mitigated by `Lsp.register`'s defensive type checks and the dispatcher's pcall-safe `attach.lua` (each subscriber is isolated).
- **Neutral:** No "auto-prompt to install extension on `FileType`" yet — that's a Phase 3+ UX decision, deliberately out of scope here. The seam is ready when we want to build it.
