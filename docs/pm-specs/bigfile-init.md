---
name: bigfile-init
description: Detect very large (or minified) files when they are opened and switch off the costly editor features for that file only, so it stays responsive
generated: 2026-11-25
---

# Summary
When you open a very large file (for example a 7 MB, 120,000-line XML export), the editor automatically turns off the features that cost the most time per keystroke and per scroll, for that file only. You get a short notice, the file stays readable and editable, and every other file keeps all its features.

---

# Problem

Opening a huge file today feels broken. Moving the cursor stutters, scrolling lags, and typing a character can freeze the editor for a moment. The editor is doing the same rich work it does for a 50-line file (coloring by grammar, drawing guides, computing the symbol trail, watching git changes, starting a language server) but on 120,000 lines, and every keypress pays for it.

Today the only protection is a small cap on bracket matching. There is no general answer, and you cannot tell whether the lag is "the file is big" or "something is wrong".

## Why now
Real work includes log files, data exports, generated code and minified bundles. The editor should open them without a fight, and tell you plainly that it has simplified itself, instead of leaving you to wonder.

---

# Target Behavior

STATE 1 - opening `realistic_orders_120k.xml` (7.4 MB, 121,112 lines):

```
┌───────────────────────────────────────────────────────────────────────┐
│                                       ┌───────────────────────────┐   │
│                                       │ Big File                  │   │
│                                       │ realistic_orders_120k.xml │   │
│                                       │ (7.4 MB) is large. Some   │   │
│                                       │ features are disabled.    │   │
│                                       └───────────────────────────┘   │
│   1  <?xml version="1.0" encoding="UTF-8"?>                           │
│   2  <!-- Synthetic deeply-nested commerce export fixture. -->        │
│   3  <commerceExport xmlns="urn:example:commerce:orders:v3" ...>      │
│   4    <orders>                                                       │
│   5      <order id="ORD-0000001" status="backordered" ...>            │
│   6        <!-- order 1: nested fixture, depth up to 14 -->           │
│   7        <parties>                                                  │
│  ...                                                                  │
│ NORMAL  realistic_orders_120k.xml            Ln 1, Col 1  XML  UTF-8  │
└───────────────────────────────────────────────────────────────────────┘
```

- One notice appears when the file opens. It names the file and its size.
- Line numbers stay. The file type stays `XML` in the statusline.
- Text is still colored (simple, fast coloring), just not the full grammar-aware kind.

---------------------------------------------------------
STATE 2 - the same file, what is switched off (invisible things you stop paying for):

```
STAYS ON                          SWITCHED OFF (this file only)
────────────────────────────────  ──────────────────────────────────────
line numbers                      grammar-aware coloring (treesitter)
simple (regex) coloring           smart indent from grammar
search, search count, replace     sticky "enclosing scope" header
editing, undo, copy/paste         indent guides and scope highlight
autopairs                         symbol trail in the winbar
statusline, tabline               language server (no LSP attach)
file explorer, finder             git change marks and inline blame
                                  smooth-scroll animation
                                  bracket-pair highlight (matchparen)
                                  folding by grammar (manual only)
                                  concealed text (conceallevel 0)
                                  extra signs and fold marks in the gutter
```

---------------------------------------------------------
STATE 3 - a normal file opened next to it:

```
┌─────────────────────────────┬─────────────────────────────┐
│ big.xml  (big file)         │ init.lua  (normal)          │
│  1  <?xml ...?>             │  1  local M = {}            │
│  2  <orders>                │  2  function M.setup()      │
│ no guides, no git marks     │ │   guides, git marks, LSP  │
└─────────────────────────────┴─────────────────────────────┘
```

Features are decided per file. A big file never changes how any other file behaves.

---

# Scenarios

## 1 - Open a big file (happy path)

```
Step 1: Run `nvim realistic_orders_120k.xml` (7.4 MB).
  The file appears. A "Big File" notice shows its name and size.

Step 2: Press j / k, Ctrl-D / Ctrl-U, G, gg, 50000G.
  The cursor and the view move immediately. No stutter, no animation delay.

Step 3: Type a character in the middle of the file.
  It appears at once. Nothing freezes while the editor "catches up".

Step 4: Search with /ORD-0099999 and press n.
  The match is found, highlighted, and the count (for example 1/1) shows as usual.
```

## 2 - Open a normal file (no change)

```
Step 1: Open lua/beast/option.lua (a few KB).
  No notice. Every feature behaves exactly as before.
```

## 3 - Minified file: small but with extremely long lines

```
Step 1: Open app.min.js (900 KB, 3 lines, average line over 1,000 characters).
  The "Big File" notice appears even though the size is under the limit.
  The long lines are the cost, so the same features are switched off.
```

## 4 - A big file and a normal file side by side

```
Step 1: In the big file, open a split with :vsplit init.lua.
  The right window shows init.lua with all its features (guides, git marks, LSP).
  The left window keeps the big file simplified.

Step 2: Move between the windows.
  Each file keeps its own behavior. Nothing leaks across.
```

## 5 - Open the same big file again later

```
Step 1: Close the buffer, then open the file again.
  The notice appears again, once for that open.

Step 2: Re-enter the same open buffer from another window or with :b.
  No new notice. Once per time the file is loaded.
```

## 6 - Edge: file does not exist yet or is empty

```
Step 1: Run `nvim new_file.xml` (not on disk) or open an empty file.
  Treated as a normal file. No notice.
```

## 7 - Edge: file grows large while editing

```
Step 1: A 200 KB file is open; paste in 10 MB of text.
  Nothing changes mid-session. The decision is made when the file opens.
  Reopen the file and it will be treated as big.
```

---

# Behavior Rules

- A file counts as big when either is true: its size on disk is over 1.5 MB, or its lines are so long on average (over 1,000 characters per line) that it looks minified. Both limits can be changed in configuration.
- The decision is per buffer and made once, when the file opens. It does not flip on later edits.
- Only that buffer is affected. Other files and the whole editor keep full behavior.
- The file type is not changed (an XML file still says `XML`), so file-type specific settings such as tabs and comment strings still apply.
- Exactly one notice per open. It is a toast, names the file, and shows the size in human units (KB / MB).
- The notice can be turned off in configuration (the features are still switched off).
- Search, search count, editing, undo, registers, the explorer and the finder are never switched off.
- The list of switched-off features is configurable, so a feature can be kept on for big files if you accept its cost.
- A feature that is switched off must stay off for the whole life of that buffer, including after `:e`, reload from disk, and re-attach events.
- Files that cannot be measured (new, empty, unreadable) are treated as normal.
- Non-file buffers (help, finder, explorer, terminal, scratch) are never treated as big.

---

# Success Criteria

- [ ] Opening `realistic_orders_120k.xml` shows exactly one "Big File" notice with name and size.
- [ ] In that file, holding `j`, `Ctrl-D` and `G` feels instant; typing a character shows immediately.
- [ ] None of the switched-off features run in that buffer (no language server attached, no treesitter coloring, no guides, no git marks, no symbol trail, no sticky header).
- [ ] Line numbers, simple coloring, search, search count, undo and statusline still work in that buffer.
- [ ] A minified 900 KB single-line-style file triggers the same behavior.
- [ ] A small file opened in the same session keeps every feature.
- [ ] A big file and a normal file in split windows each keep their own behavior.
- [ ] The file type of a big file is still shown (XML for the sample file).
- [ ] Turning the notice off in configuration silences it without re-enabling features.
- [ ] Reopening the same big file shows the notice again once per open.

---

# Out of Scope

- A command or key to switch the features back on for one big file (an escape hatch). Deferred until the need is real.
- Re-evaluating a buffer that grows past the limit during a session.
- A "BIG" indicator in the statusline. The notice is enough for the first version.
- Special handling of very large files in the finder preview or the explorer.
- Streaming or partial loading of files (only editing a window of the file). The whole file is still loaded.
- Opening binary files differently.
