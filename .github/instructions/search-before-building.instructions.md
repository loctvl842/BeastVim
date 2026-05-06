---
description: "Use when about to write a new utility, helper, abstraction, or add functionality. Search the repo and package registries before writing custom code."
---

# Search Before Building

Before writing a new utility, helper, or adding functionality:

1. **Search the repo first** — grep for related functions, check `lua/beast/util/`, `lua/beast/libs/view.lua`, `lua/beast/libs/animate.lua`, and `AGENTS.md` § *Shared Modules Registry* for what's already shared. Also check `AGENTS.md` § *Known DRY Opportunities* — your problem may be the third instance of an already-flagged pattern.
2. **Search Neovim core first** — `vim.api.*`, `vim.fn.*`, `vim.uv.*`, `vim.schedule_wrap`, `vim.system`, `vim.ui.*`. Native APIs almost always beat plugins for this project.
3. **Search the plugin ecosystem only if core can't do it** — and only if the dependency is well-maintained, permissive license, and not already covered by a wrapper in `lua/beast/plugins/`.
4. **If found** — reuse or extend what exists instead of writing new code.
5. **If not found** — proceed with custom code, but mention you searched (this becomes the dev spec's `## Research` section if a spec is being written).

Don't reinvent the wheel. Don't write custom code when a Neovim primitive exists.
