---
name: markdown-lists
description: A markdown language plugin that continues, numbers, indents and exits lists automatically while typing
generated: 2026-11-05
---

# Summary
A new `markdown` language plugin, sitting next to python, cpp and json. When writing markdown, pressing Enter inside a list starts the next item for you (same bullet, next number, empty checkbox), and Tab / Shift-Tab nest and un-nest items with numbers kept correct.

---

# Problem

Writing notes, READMEs and AI prompts in markdown means a lot of lists. Today, pressing Enter at the end of a list item gives a blank line. You have to type `- ` or `3. ` again, match the indentation by hand, and fix every number yourself when you insert or move an item. Leaving the list means deleting the marker you do not want. It is small friction, but it happens on every line.

## Why now
Markdown is now a daily format (docs, prompts, plans, agent instructions). Language support already exists for code languages; markdown is the missing one. It also needs the markdown parser ensured so highlighting is consistent.

---

# Target Behavior

`|` marks the cursor.

```
STATE 1 - Bullet continues:
  - buy milk|            <Enter>
  - buy milk
  - |

─────────────────────────────────────────
STATE 2 - Ordered list auto-increments:
  1. first|              <Enter>
  1. first
  2. |

─────────────────────────────────────────
STATE 3 - Task list continues with an empty box:
  - [x] write spec|      <Enter>
  - [x] write spec
  - [ ] |

─────────────────────────────────────────
STATE 4 - Empty item exits the list:
  - buy milk
  - |                    <Enter>
  - buy milk
  |

─────────────────────────────────────────
STATE 5 - Tab nests, Shift-Tab un-nests:
  1. first
  2. |                    <Tab>
  1. first
      1. |

  (<S-Tab> brings it back to "2. |")
```

---

# Scenarios

## 1 - Continue a bullet list (happy path)

```
Step 1: Type "- apples" and press Enter
  A new line starts with "- " and the cursor after it.

Step 2: Type "oranges"
  - apples
  - oranges|
```

The marker style is kept: `-`, `*` and `+` each continue as themselves.

## 2 - Ordered list numbering

```
Step 1: Type "1. one", Enter, "two", Enter
  1. one
  2. two
  3. |

Step 2: Put the cursor at the end of "1. one" and press Enter, type "inserted"
  1. one
  2. inserted|
  3. two
  4. three
```

Numbers below the new item are renumbered so the list stays consecutive. Both `1.` and `1)` styles are kept.

## 3 - Nested lists keep their indent

```
Step 1: On "  - child|" press Enter
  - parent
    - child
    - |
```

## 4 - Task lists

```
Step 1: On "- [ ] todo|" press Enter
  - [ ] todo
  - [ ] |

Step 2: On "- [x] done|" press Enter
  - [x] done
  - [ ] |
```

New task items always start unchecked.

## 5 - Leaving a list (edge case)

```
Step 1: On an item with only a marker, "- |", press Enter
  The marker is removed and the line becomes empty.
  - last item
  |

Step 2: On an indented empty item "    - |", press Enter
  It moves up one level instead of leaving the list:
  - parent
  - |
```

## 6 - Enter in the middle of an item

```
Before:  - buy |milk and eggs
Enter:
  - buy
  - |milk and eggs
```

The text after the cursor moves to the new item with the marker.

## 7 - Not in a list (no surprises)

```
Step 1: On a plain paragraph line, press Enter
  Normal new line, nothing inserted.

Step 2: Inside a fenced code block, press Enter on a line that looks like "- x"
  Normal new line. Code is never treated as a list.
```

## 8 - Nest and un-nest with numbers fixed

```
Step 1: On "3. |" (empty), press Tab
  1. a
  2. b
      1. |

Step 2: Press Shift-Tab
  1. a
  2. b
  3. |
```

Nested ordered items restart at 1 and the outer list continues from the right number.

## 9 - `o` / `O` in normal mode

```
On "- item" press o:
  - item
  - |        (insert mode)
```

Opening a line below an item behaves like Enter at the end of it.

---

# Behavior Rules

- Only active in markdown buffers; every other filetype keeps its normal Enter and Tab.
- Enter continues the list only when the cursor is after the marker. Cursor inside the marker or indent keeps a plain newline.
- Markers recognised: `-`, `*`, `+`, `1.`, `1)`, and each of these followed by `[ ]` / `[x]`.
- Ordered lists continue with the next number. Following items in the same list are renumbered; unrelated lists are untouched.
- Enter on an empty item un-nests one level if nested, otherwise removes the marker.
- Tab / Shift-Tab only change nesting when the cursor line is a list item; elsewhere they behave as usual (completion menu and snippet jumps keep priority).
- Lines inside fenced code blocks are never treated as list items.
- A block quote prefix (`> - item`) is continued as well.
- One undo step reverts the whole Enter (new line and marker together).
- Existing behavior is untouched: render-markdown, autopairs fence expansion, and the completion menu still work. Enter while the completion menu is open accepts the item as before.
- The markdown tree-sitter parser is installed and enabled automatically.
- Any message for the user is shown as a toast, never a command-line prompt.

---

# Success Criteria

- [ ] Enter at the end of `-`, `*`, `+` items starts a new item with the same marker and indent
- [ ] Enter on `1.` / `1)` items gives the next number, and following items are renumbered
- [ ] Enter on a task item gives an unchecked box
- [ ] Enter on an empty item exits the list (or un-nests one level)
- [ ] Enter mid-item splits the text and moves the rest to the new item
- [ ] Tab / Shift-Tab nest and un-nest with correct numbering
- [ ] `o` / `O` continue the list
- [ ] No change in code blocks, plain paragraphs, or non-markdown files
- [ ] Completion menu and autopairs keep working with Enter
- [ ] Opening a markdown file loads the plugin lazily with no startup cost elsewhere

---

# Out of Scope

- Formatting / reflowing markdown (a formatter such as prettier can be a later addition)
- Language server, link checking, table editing - deferred, separate features
- Toggling checkboxes or converting lines to lists via a command - deferred
- Rendering and preview - already handled by the render-markdown plugin
- Smart continuation in other text-like filetypes (`text`, `gitcommit`) - deferred
