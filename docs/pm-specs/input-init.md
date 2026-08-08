---
name: input-init
description: Context-aware floating replacement for vim.ui.input, anchored to the cursor when possible
generated: 2026-08-09
---

# Summary

Input replaces Neovim's plain command-line `vim.ui.input` prompt with a themed floating box that appears near the text being edited — anchored to the cursor and word when there's meaningful context (like renaming a symbol), or centered near the top of the screen when there isn't. The call contract (prompt, default, completion, highlight) stays identical to the native API.

---

# Problem

Today, anything that calls `vim.ui.input` - renaming a symbol, naming a new file, typing a commit message - shows a plain single-line prompt at the very bottom of the screen. It looks like a generic command-line message, gives no visual link to what's actually being edited, and looks inconsistent with the rest of BeastVim's floating dialogs (the Yes/No confirm dialog and the finder's search box already got a themed, bordered redesign).

## Why now

Confirm dialogs and the finder search box already got a consistent, polished floating treatment. `vim.ui.input` is the last major native-styled surface left, and it's also one of the most frequently triggered (renames, commit messages, file names) - so it's the most visible remaining gap in BeastVim's UI consistency.

---

# Target Behavior

```
STATE 1 — Cursor-anchored, above (default, e.g. renaming a symbol):

  1  function calculateTotal() {
       ╭─ Rename to ─────────────────╮
       │ oldName█                    │
       ╰──────────────────────────────╯
  2    const oldName = getValue()
                ▔▔▔▔▔▔▔  (word under cursor)
  3    return oldName * 2
  4  }
```

```
STATE 2 — Cursor-anchored, flipped below (not enough room above, e.g. cursor near top of screen):

  1  const oldName = getValue()
              ▔▔▔▔▔▔▔  (word under cursor, near top of screen)
       ╭─ Rename to ─────────────────╮
       │ oldName█                    │
       ╰──────────────────────────────╯
  2    return oldName * 2
```

```
STATE 3 — Centered fallback (no meaningful cursor anchor, e.g. a commit message prompt):

                  ╭─ Commit message ─────────────────────────╮
                  │ Fix login redirect loop█                  │
                  ╰────────────────────────────────────────────╯

           (positioned in the upper area of the screen, horizontally
            centered — not dead-center like the confirm dialog)
```

```
STATE 4 — With completion (opts.completion set, e.g. switching branches):

       ╭─ Switch branch ──────────────╮
       │ fea█                         │
       ├───────────────────────────────┤
       │ feature/login-redesign        │
       │ feature/payment-retry         │
       ╰────────────────────────────────╯
```

---

# Scenarios

## 1 — Renaming a symbol (happy path, cursor-anchored above)

```
Step 1: The user triggers a rename on a symbol under the cursor.
  A bordered input box appears directly above the cursor's line, titled
  with the rename prompt. The current name is pre-filled, cursor placed
  at the end of it, ready to edit.

Step 2: The user edits the name and presses Enter.
  The box closes and the new name is returned to the caller, exactly as
  native vim.ui.input would.
```

## 2 — Renaming near the top of the screen (edge case, flips below)

```
Step 1: The user triggers the same rename, but the cursor's line is near
the top of the visible window, leaving no room to draw the box above it.
  The input box appears anchored below the cursor's line instead - still
  directly tied to the word being renamed, just flipped.

Step 2: The user completes the rename as normal.
  Behavior is otherwise identical to Scenario 1.
```

## 3 — A prompt with no meaningful anchor (e.g. commit message)

```
Step 1: The user triggers an input prompt that isn't tied to any specific
buffer text (for example, entering a commit message).
  The input box appears as a centered overlay in the upper area of the
  screen, instead of anchoring to an arbitrary cursor position.

Step 2: The user types the message and confirms.
  The box closes and the text is returned to the caller.
```

## 4 — Cancelling the input

```
Step 1: The user opens any input prompt.
  The box appears as described in the relevant state above.

Step 2: The user presses Esc.
  The box closes immediately and the caller receives no input (nil),
  exactly matching native vim.ui.input cancellation behavior.
```

## 5 — Completion-assisted input

```
Step 1: The user triggers a prompt that offers completions (e.g. branch
switching).
  The input box appears as usual, anchored per the rules above.

Step 2: The user starts typing and triggers completion.
  A list of matching suggestions appears attached to the bottom of the
  input box.

Step 3: The user picks a suggestion and confirms.
  The box closes and the chosen text is returned to the caller.
```

---

# Behavior Rules

- The call contract is unchanged: prompt, default text, completion source, and the live highlight callback all behave exactly as documented for native `vim.ui.input` - only the visual presentation changes.
- Default text (if provided) is pre-filled with the cursor placed at the end, matching native behavior - not pre-selected/highlighted for full replacement.
- Cursor-anchored mode prefers appearing above the cursor's line; if there isn't room, it flips to below instead of overlapping content or going off-screen.
- The centered fallback is used only when there's no meaningful buffer/cursor context to anchor to - not merely when there's no room (that case flips instead, per the rule above).
- Both positioning modes share the same visual chrome (rounded border, prompt shown as the box title, BeastVim theme colors) for consistency with the confirm dialog and finder search box.
- Esc (or leaving the window) cancels the prompt and returns nil to the caller, matching native cancellation semantics.
- When no UI is attached (headless), input falls back to native `vim.ui.input` behavior, consistent with how the confirm dialog already handles headless mode.

---

# Success Criteria

- [ ] Renaming a symbol shows the input anchored above the word under the cursor.
- [ ] When there's no room above, the input flips to below the cursor instead of overlapping code or the window edge.
- [ ] Prompts with no meaningful buffer context appear as a centered, near-top overlay instead of anchoring arbitrarily.
- [ ] Cancelling with Esc returns nil to the caller, matching native `vim.ui.input`.
- [ ] Completion and highlight callbacks work exactly as documented for native `vim.ui.input`.
- [ ] Visual style (border, colors, title) matches BeastVim's existing confirm dialog and finder search box.
- [ ] Every existing caller of `vim.ui.input` in BeastVim (and any plugin relying on it) continues to work without changes to its own code.

---

# Out of Scope

- Multi-line input (native `vim.ui.input` is single-line only; not being extended)
- Input history navigation between separate prompt invocations (dressing.nvim has this, but it wasn't requested - can be a follow-up spec)
- Any change to the `opts`/`on_confirm` call contract itself
