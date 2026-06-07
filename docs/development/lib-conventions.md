# Library Code Conventions

This is the canonical checklist for any new lib under `lua/beast/libs/<name>/`.
Existing libs should converge on these rules whenever they are touched.

Living document — add a row when a new pattern is agreed on; remove rows that
no longer reflect reality.

## 1. Layout

```
libs/<name>/
├── init.lua         -- public API + M.setup(opts)
├── config.lua       -- defaults, types, read-only proxy
├── highlights.lua   -- M.get() returns Util.colors.build("Beast<Name>", {...})
├── <submodules>.lua -- one responsibility each (state, ui, render, ...)
└── <submodule>/     -- folder + init.lua when a submodule itself splits
```

- A submodule grows a folder once it exceeds ~250 LOC or has 3+ distinct
  responsibilities. Each split file stays focused on one job.
- File names are lowercase, single-word when possible (`state`, `render`,
  `loop`, `window`). Avoid suffixes like `_state`, `_helpers`.

## 2. Config (`config.lua`)

**One config module per lib. It is the single source of truth.**

- Wrap a local `cfg` table behind a read-only metatable proxy:

  ```lua
  local M = setmetatable({}, {
    __index = function(_, key)
      if methods[key] ~= nil then return methods[key] end
      return cfg[key]
    end,
    __newindex = function(_, key, _)
      error(string.format("beast.<name>.config is read-only; cannot assign '%s' directly. Use setup() instead.", tostring(key)), 2)
    end,
  })
  ```

- `M.setup(opts)` is the **only** writer. It runs once, from the lib's top-level
  `init.lua:M.setup`:

  ```lua
  function methods.setup(opts)
    cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  end
  ```

- **Submodules MUST NOT have their own `setup(cfg)` for config-passing.** They
  read directly: `local config = require("beast.libs.<name>.config")` and
  reference `config.foo.bar` at call time. This keeps a single source of
  truth and avoids drift.
- Submodules MAY have a `setup()` that performs side-effects (autocmd
  registration, trigger registration). They take no config args.
- All public config fields are documented with `---@class Beast.<Name>.Config`
  annotations co-located with `defaults`.

## 3. Public API (`init.lua`)

- Requires its own `config` and all submodules at the top.
- Exposes the lib's public surface only — internal helpers stay in submodules.
- `M.setup(opts)` is the single entry point. Order:

  ```lua
  function M.setup(opts)
    require("beast.libs.<name>.builtin")            -- if any (eager side-effects)
    require("beast").apply_highlights("beast.libs.<name>.highlights")
    config.setup(opts)                              -- writes cfg once
    -- post-config setup of optional submodules:
    if config.feature and config.feature.enabled then
      require("beast.libs.<name>.feature").setup()
    end
  end
  ```

- Avoid re-exporting submodule internals through `init.lua` unless they form
  part of the documented public API.

## 4. Highlights (`highlights.lua`)

- Exposes `M.get()` returning a table built via:

  ```lua
  return Util.colors.build("Beast<Name>", { Normal = {...}, Border = {...}, ... })
  ```

- All HL groups share the `Beast<Name>` prefix (sub-feature suffix optional:
  `BeastKeyHint*`). No other module hard-codes raw highlight names; callers
  reference the resolved names (`"BeastKeyHintBorder"`) directly.

## 5. View / windows

- UI submodules build on `beast.libs.view` (`View:new` / `View:extend`). Do
  not write bare `nvim_open_win` UIs without wrapping them in a `Beast.View`.
- Never set `view.buf` or `view.win` to `nil`. Use `false` (or call
  `view:close()`) — see ADR-???: namespace cascade fix.
- **Writing window-local options at setup**: use `vim.go.<opt>` for the
  global default and `nvim_set_option_value(opt, val, { win = w })` for any
  already-open windows you want to retro-apply to. Do **not** use
  `vim.o.<opt>` — it stamps the current window's local value, which is
  wrong when setup fires while a `style = "minimal"` float is current
  (e.g. the packer install UI on first start). That float already carries
  a window-local override; writing through it leaves the global empty and
  newly-spawned plain windows have nothing to inherit. See
  `lua/beast/libs/statuscolumn/init.lua:setup` for the pattern.

## 6. Submodule responsibilities

Split a lib by responsibility, not by file size. Typical roles:

| File          | Responsibility                                          |
| ------------- | ------------------------------------------------------- |
| `init.lua`    | Public API, lifecycle, glue                             |
| `config.lua`  | Defaults + read-only proxy                              |
| `state.lua`   | Shared mutable state for the lib's session              |
| `ui.lua`      | Composes Views; no business logic                       |
| `render.lua`  | Pure layout / line / extmark generation                 |
| `loop.lua`    | Modal `getchar` / event loops                           |
| `index.lua`   | Lookup structures + cache + invalidation                |
| `autocmds.lua`| Autocmd group + handlers                                |
| `keymaps.lua` | Buffer-local keymaps                                    |
| `api.lua`     | Pure data access (collect / filter / format entries)    |
| `health.lua`  | `:checkhealth` integration                              |
| `builtin.lua` | Default keymaps / commands registered at setup          |

Not every lib needs every file — only what the responsibility justifies.

## 7. Performance / cache invalidation

- Cache anything derived from `Key.managed`, file scans, or expensive
  computations, but always invalidate via a single explicit signal (User
  autocmd, e.g. `BeastKeysChanged`). Never rely on polling timers.
- Expose a `module.invalidate()` for caches. Submodules listen to the User
  autocmd from the lib's top-level setup, not from inside helper modules.
- **Per-item highlighting**: when a list view re-renders on every keystroke
  (finder, picker, explorer), do **not** stamp `nvim_buf_set_extmark` per
  item up-front. Use `nvim_set_decoration_provider` with `on_win` / `on_line`
  and `ephemeral = true` extmarks instead — the callback only fires for
  lines about to be drawn, so a 500-item buffer with a 10-line viewport
  does ~10 stamps per redraw instead of 500. The two patterns we already
  have:
  - `lua/beast/libs/finder/match_hl.lua` — fuzzy match highlights on the
    visible slice of the result list + preview buffer.
  - `lua/beast/libs/indent/init.lua` — indent guides.

  Persistent annotations that outlive a redraw (sign-column gutters,
  diagnostic underlines, comment-toggle markers) still want regular
  buffer-scoped extmarks. The rule is *transient per-redraw decoration →
  provider, persistent state → extmark*.
- **Statuscolumn rendering**: do not implement statuscolumn logic via
  decoration providers. The native `%!v:lua...` callback is per-visible-
  screen-line by default and Neovim caches the result. See
  `beast.libs.statuscolumn` for the production pattern.

## 8. Tests + benches

- A bench script lives at `scripts/bench-<lib>.lua`. Final line must be
  `BENCH name=<lib> ... status=PASS|FAIL`. Use exit code 0/1/2.
- Hot paths (anything fired per keystroke, per render, per autocmd) MUST have
  a measurement in the bench.
- Manual repros live at `tests/test-<lib>.lua`. Runnable with
  `nvim --clean -u tests/test-<lib>.lua`.

## 9. Documentation

- Add the lib to `docs/CODEMAPS/libraries.md` with a file-tree summary.
- Decisions (why X not Y) go in an ADR under `docs/ADRs/`.
- Feature plans live in `docs/dev-specs/`.

## Quick PR checklist

- [ ] `config.lua` follows the read-only proxy pattern; no extra
      `setup(cfg)` in submodules
- [ ] All submodules read shared config via `require("beast.libs.<name>.config")`
- [ ] Highlights live in `highlights.lua` with `Beast<Name>` prefix
- [ ] UI built on `Beast.View`; no bare `nvim_open_win` business logic
- [ ] `init.lua:M.setup` is the only entry point
- [ ] Caches invalidated via User autocmd, not timer polling
- [ ] Bench script exists and PASSes
- [ ] Lib appears in `docs/CODEMAPS/libraries.md`
- [ ] `stylua --check lua/` clean
