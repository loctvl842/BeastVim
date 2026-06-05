# Lazy-loading & event triggers — when to `defer`

> See also: [`benchmarking.md`](./benchmarking.md) §"Startup regressed", and `lua/beast/libs/packer/` for the implementation.

BeastVim's libs and plugins are lazy-loaded via `packer.lazy()` (libs) and plugin specs (`lazy = { ... }`). Six trigger types are available: `event`, `keys`, `cmd`, `module`, `filetype`, `path`.

**Only the `event` trigger supports `defer`.** Every other trigger has something (a user, a `require` caller, the redraw cycle) actively waiting on the result, so deferring would either break the contract or add visible lag.

---

## The mental model

```lua
event = { name = "VimEnter", defer = true }
                              ^^^^^^^^^^^^
                              "I don't need to be ready before first paint —
                               run me on the next event-loop tick instead."
```

`defer = true` wraps the load in `vim.schedule()`. The autocmd handler returns immediately; the lib's `setup()` runs ~1 frame later. **The total work is the same** — only *when* it runs shifts. Cost is paid either way; the user just sees the cursor sooner.

> Defer does **nothing** for headless benchmarks (`+qa` drains the schedule queue before exit). It only improves *perceived* interactive startup. Don't chase it for wall-clock numbers; chase it for UX.

---

## When to defer (which events get `defer = true`)

| Event | Defer? | Reason |
|---|---|---|
| `VimEnter` | ✅ Yes | Fires once at startup; nothing else is waiting on it |
| `UIEnter` | ✅ Yes | Same as VimEnter; UI is now up, work can wait one tick |
| `BufEnter` | ✅ Yes *if* `setup()` manually processes the current buffer | Otherwise the in-flight `BufEnter` is missed; only future buffers get handled |
| `BufReadPost` / `BufNewFile` | ✅ Yes | Same caveat as `BufEnter` — handle current buf in `setup()` |
| `WinEnter` / `WinNew` | ✅ Yes | Cosmetic / window-decoration libs can paint one frame late |
| `FileType` | ⚠️ Borderline | Highlight attach is render-critical — one frame of unstyled text is visible. BeastVim defers treesitter today; flip to `defer = false` if you see filetype flash |
| `BufWritePre` / `BufWritePost` | ❌ Never | Mid-save — formatters / pre-write hooks **must** finish before the write |
| `LspAttach` | ❌ Never | Keymaps / handlers must be registered for the in-flight client |
| `CursorMoved*` / `TextChanged*` | ❌ Never | The state being reacted to is *current* — defer = act on stale state |
| `CmdlineEnter` / `CmdlineLeave` | ❌ Never | User is mid-keystroke; latency is felt |
| `User <Pattern>` | depends | Defer iff the publisher doesn't need the subscriber to act synchronously |

---

## When NOT to defer (entire trigger types)

| Trigger | Why no `defer` |
|---|---|
| `keys` | User pressed a key and is **actively waiting**. Deferring = visible input lag. |
| `cmd` | User typed `:Foo<CR>`. Same as keys. |
| `module` | `require("X")` is awaiting a return value; `vim.schedule(load)` would return nothing and break the require chain. |
| `filetype` | Render-critical (treesitter, LSP, syntax) — must attach before next paint. |
| `path` | The user just opened a file/dir; the handler must take effect now. |

This is why `defer` lives **inside** the event spec, not at the top level of the `lazy()` opts. The packer API enforces that intent.

---

## Spec syntax

```lua
-- Single event, sync (default for bare strings)
event = "FileType"

-- Single event, deferred
event = { name = "VimEnter", defer = true }

-- Multiple events, all sync
event = { "BufReadPost", "BufNewFile" }

-- Multiple events, mixed defer settings
event = {
  { name = "BufReadPost", defer = true },   -- cosmetic; ok to defer
  { name = "BufWritePre", defer = false },  -- must run before save
}

-- With pattern (e.g. User events, FileType filtering)
event = { name = "User",     pattern = "BeastGitChanged", defer = true }
event = { name = "FileType", pattern = "lua",             defer = false }
```

---

## The "first event miss" gotcha

When `packer.lazy()` registers an event trigger, the load happens **on** the trigger event. If the lib's `setup()` only does `vim.api.nvim_create_autocmd(<same event>, ...)`, it registers for **future** events — the current one is already gone. Symptoms: lib loads on the first buffer open but doesn't act on it; second buffer onwards works fine.

The defer-safe `setup()` pattern:

```lua
function M.setup(opts)
  -- 1. Wire the autocmd for FUTURE events
  vim.api.nvim_create_autocmd("BufReadPost", { callback = on_buf_read })

  -- 2. Manually process the CURRENT state (the event that loaded us)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      on_buf_read({ buf = buf })
    end
  end
end
```

Do this whether or not the lib is deferred — it's correct for any event-triggered lib that needs per-buffer state.

---

## Quick checklist when writing a new `packer.lazy()` spec

1. **Is the trigger render-critical?** (FileType for treesitter, BufWritePre for formatter) → `defer = false`.
2. **Is the lib purely cosmetic?** (winbar, tabline, indent guides, scroll animation) → `defer = true`.
3. **Does `setup()` process the current state?** If no, fix that before deferring.
4. **Is there a `keys` trigger?** Confirm those keymaps load the lib **synchronously** (they do automatically — keys never defer).
5. **Verify wall-clock σ stays low.** A spike in startup variance after adding a deferred event is a sign your `setup()` is racing the schedule queue.

---

## Reading list when in doubt

- The full lifecycle walkthrough: ask the `tec-debug` skill or read `docs/neovim/latency-research.md`.
- Event semantics: `:help autocmd-events`.
- `vim.schedule` semantics: `:help vim.schedule()` and `src/nvim/lua/executor.c`'s `nlua_schedule`.
