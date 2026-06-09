# ADR-031: `Lsp.register(name, cfg)` API Shape — `keys` and `on_attach` as BeastVim Extensions

**Status:** Accepted

**Date:** 2026-06-08

**Evidence:** `lua/beast/libs/lsp/init.lua` (`BEAST_FIELDS`, `split_spec`, `M.register`); `lua/beast/libs/lsp/attach.lua` (dispatcher ordering); `lua/beast/libs/lsp/keys.lua` (`cond` gating via `client:supports_method`, `Key.safe_set`); `lua/beast/libs/key/core.lua:151` (`Key.safe_set`); dev spec `docs/dev-specs/lsp-library.md` § *API*; related: ADR-029 (native LSP infra), ADR-030 (extension ownership).

## Context

`Lsp.register(name, cfg)` is the public contract that every future `BeastVim/<Lang>` extension calls. Once a few extensions depend on it, changing it is a coordination problem across N repos. Freezing the shape intentionally now — before there are downstream consumers — is the cheapest time to do it.

Native `vim.lsp.config(name, cfg)` accepts a `vim.lsp.Config` table: `cmd`, `root_markers`, `filetypes`, `settings`, `capabilities`, `on_attach`, etc. BeastVim needs two things that aren't in that table:

1. A way to declare **buffer-local keymaps that only bind when the server supports the relevant LSP method** (e.g. `gD` only if `textDocument/definition` is supported). Native `on_attach` can do this manually but the boilerplate repeats per server.
2. A `keys` shape consistent with the rest of the distro — `Key.safe_set` is already the codebase's keymap primitive (`lua/beast/libs/key/core.lua:151`), and folding LSP keymaps into the same lookup tools is the whole point of having one.

## Decision

1. **Accept a `vim.lsp.Config` augmented with two BeastVim-only fields.** The augmented shape:
   ```lua
   Lsp.register("lua_ls", {
     -- standard vim.lsp.Config fields (passed through to vim.lsp.config):
     cmd = { "lua-language-server" },
     filetypes = { "lua" },
     root_markers = { ".luarc.json", ".luarc.jsonc", ".git" },
     settings = { Lua = { ... } },
     -- BeastVim extensions (split out before passthrough):
     keys = {
       { "gD", vim.lsp.buf.declaration, desc = "Declaration", cond = "textDocument/declaration" },
       { "K",  vim.lsp.buf.hover,       desc = "Hover",       cond = "textDocument/hover" },
     },
     on_attach = function(client, bufnr) ... end,
   })
   ```
2. **Split the spec with a fixed allowlist.** `BEAST_FIELDS = { keys = true, on_attach = true }` at the top of `init.lua` declares which fields are pulled out before the rest is handed to `vim.lsp.config`. `split_spec(cfg)` returns `(native_cfg, extras)` where `extras` carries `keys`/`on_attach`.
3. **Dispatch order is fixed by the file, not by registration**: per-server keys bind first, then per-server `on_attach` runs, then global subscribers (registered via `Lsp.on_attach(fn)`) run in registration order. This means a global subscriber can always see what per-server hooks have done.
4. **`keys[].cond` gates by LSP method.** When set, `client:supports_method(cond)` is checked at attach time. If false, the keymap is skipped — no error, no warning, just not bound. `keys[].cond` may be a string (LSP method) or a function `(client, bufnr) -> boolean` for arbitrary predicates.
5. **All keymaps are bound via `Key.safe_set`** (buffer-local, `buffer = bufnr`). Matches the codebase's existing keymap layer, so `:Key` introspection works on LSP keymaps the same as any other.

## Alternatives Considered

1. **Accept only a plain `vim.lsp.Config`, no BeastVim extensions.** Force lang extensions to do their own `LspAttach` autocmd + their own `Key.safe_set` calls. Rejected — pushes the same 10-line boilerplate into every extension repo. The whole point of the lib is to not have that boilerplate in N places.
2. **Open-ended split** (every non-`vim.lsp.Config` key gets pulled into `extras`). Rejected — silent typos become silent feature loss (`on_atatch` would just be dropped). The explicit allowlist surfaces typos via the passthrough (`vim.lsp.config` will complain about unknown fields it doesn't recognize, which catches misspellings).
3. **Separate `Lsp.register_keys(server, keys)` API.** Rejected — splits one logical operation ("here's how to set up this server") into two calls. Lang extensions would always pair them; the call sites would always look the same. Better to keep them in one cfg table.
4. **`keys` as a flat list of `vim.lsp.buf.*` method names** (`keys = { "gD", "K", "rn" }`). Rejected — too magic, not extensible (the user can't bind a custom function), and not consistent with the codebase's existing `{ lhs, rhs, desc, ... }` table shape used elsewhere.
5. **`cond` only accepts a string LSP method.** Rejected — forecloses on legitimate predicates like "only bind in tsserver attached buffers when the file is not in node_modules". The function form costs one `type()` check at attach time and unlocks the escape hatch.

## Rationale

1. **Augmenting > replacing.** The native fields stay native (`vim.lsp.config` is the source of truth for their semantics). Only the BeastVim-specific behavior (`keys`, `on_attach`) gets pulled out. Lang extension authors who know `vim.lsp.Config` already know 95% of the API.
2. **The allowlist is small and stable.** Two fields means two things to remember. If a third extension field becomes necessary later (e.g. `formatters`, `linters`), adding it is a single-line change to `BEAST_FIELDS` — but the bar to add a field is "every lang extension would write this, and writing it manually is non-trivial". That bar has not been met by anything beyond `keys` and `on_attach`.
3. **`client:supports_method` is the right gate.** Binding a keymap that calls `vim.lsp.buf.definition()` when the server doesn't support `textDocument/definition` means hitting the keymap silently does nothing — a UX bug. The `cond` check turns it into "the keymap isn't there", which is honest. Plus `:Key` introspection won't lie about what's bound.
4. **`Key.safe_set` keeps one keymap layer.** Every keymap in BeastVim flows through `Key.safe_set`. LSP keymaps shouldn't be a special case — that would split keymap introspection, conflict detection, and the popup UI into two regimes.
5. **Dispatch order matters for predictability.** Per-server hooks before global subscribers means a global "log all LSP attaches" subscriber sees a fully-set-up buffer. Reversing it would mean the logger sees a partial state. The chosen order is the one that minimizes surprise.

## Consequences

- **Positive:** Lang extensions become declarative. The `BeastVim/Lua` extension's entire LSP block is the cfg table — no `LspAttach` autocmd, no manual `client.supports_method` checks, no `vim.keymap.set` boilerplate.
- **Positive:** `:Key` introspection covers LSP keymaps for free (they go through `Key.safe_set`).
- **Positive:** Adding a global concern (e.g. "always run inlay-hints toggle on attach") is `Lsp.on_attach(fn)` from anywhere — no per-extension changes needed.
- **Negative:** The contract is now versioned. Renaming `keys` → `keymaps` post-launch breaks every extension. Mitigated by freezing the shape *before* extensions exist (this ADR).
- **Negative:** Capabilities are snapshotted in `register()` at call time (see ADR-029). Extensions calling `Lsp.add_capabilities(...)` *after* `Lsp.register(...)` won't see the contribution. Ordering is enforced by convention: capability contributors register in `beast/init.lua` (eager), lang extensions register their server in their own `setup(ctx)` (later). Document on the README of every `BeastVim/<Lang>` repo.
  - **Update 2026-06-09:** Mostly resolved. `register()` now stamps a capabilities snapshot at call time (Neovim's `vim.lsp` validator strictly requires a `table` — an earlier attempt to use a function thunk failed at runtime: `capabilities: expected table, got function`) **and** installs a chained `before_init` hook that re-resolves `M.capabilities()` at the moment the LSP `initialize` request is built. Net effect: contributors registered any time before a given server *starts* reach that server, regardless of `register()` ordering. The only remaining case is contributors added after a client has already connected — those won't reach the already-running client, and `capabilities.add()` emits a one-shot `vim.notify` WARN in that scenario. See dev spec `docs/dev-specs/lsp-infra-hardening.md`.
- **Neutral:** `cond` as a function gives extensions a foot-gun (arbitrary predicates run on every attach). Acceptable — same risk profile as any `on_attach` body.
