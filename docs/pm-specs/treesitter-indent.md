---
name: treesitter-indent
description: Indent new and existing lines using the buffer's syntax structure
generated: 2026-08-02
---

# Summary

Indentation should follow the real nesting of the code (tags, blocks, brackets) instead of generic per-filetype guesswork. This applies everywhere a parser is available, without needing a separate plugin.

---

# Problem

Today, pressing `o`/`O` to open a new line, or typing a closing character, produces indentation from Neovim's built-in filetype rules. Those rules only recognize a small set of generic patterns (matching brackets and a handful of keywords) and have no idea about markup-style nesting such as component tags.

Concretely: opening a new line right after a tag that starts a block does not step the new line in — it lands at the same depth as the tag that just opened, instead of one level deeper to match the content that follows. The same class of problem shows up any time the buffer's real structure is deeper or shallower than what the generic rules can infer, so line after line drifts out of alignment and has to be fixed by hand.

## Why now

Highlighting and folding already follow the buffer's real syntax structure. Indentation is the one remaining everyday action that still relies on the older, generic guesswork, and it's the one that fires on every single `Enter`/`o` — so the mismatch is felt constantly, not just occasionally.

---

# Target Behavior

STATE 1 — Opening a line inside a nested tag:
```
33  <footer className="border-t border-footer-border bg-background">
34  ▏
35    <div className="container mx-auto px-6 py-6">
36      <div className="grid grid-cols-1 md:grid-cols-2 gap-8 md:gap-12">
37        {/* Left Column: Identity & Navigation */}
```
The cursor on line 34 lands indented one level deeper than `<footer>`, matching the `<div>` that already sits inside it — not flush with `<footer>` itself.

STATE 2 — Typing a closing character:
```
12  function greet() {
13    console.log("hi")
14  }█
```
Typing `}` on an empty, over-indented line snaps it back to line 12's depth, instead of staying at the deeper level.

STATE 3 — No parser available for the filetype:
```
1   some content
2   █
```
Indentation quietly falls back to Neovim's normal per-filetype behavior. Nothing errors, nothing looks broken — it just isn't structure-aware for that filetype.

---

# Scenarios

## 1 — Opening a new line inside a nested block (happy path)

```
Step 1: Cursor sits on a line that opens a block (a tag, `{`, `(`, etc.), with nested content already below it.
  The block visibly contains further-indented lines.

Step 2: Press `o` to open a new line below.
  The new, empty line is indented one level deeper than the opening line — matching the depth of the content that already lives inside that block.

Step 3: Type content and press Enter again while still inside the block.
  Indentation stays at the same nested depth, not drifting.
```

## 2 — Closing a block

```
Step 1: Inside an open block, add a new line and type the block's closing character (`}`, `)`, a closing tag, etc.).
  As soon as the closing character is typed, the line un-indents to line up with the line that opened the block.
```

## 3 — Blank lines and comments

```
Step 1: Open a new line inside a block and leave it empty, or type only a comment.
  The line is indented to a sensible depth (matching its surrounding content) rather than being forced to a rigid rule that fights with the writer's intent.
```

## 4 — Deeply nested structure

```
Step 1: Place the cursor several levels deep (e.g. a tag inside a tag inside a function body).
  Step 2: Open a new line.
  The new line lands at the correct cumulative depth for all the levels it's nested inside — not just one level relative to the immediate parent.
```

## 5 — Filetype without a parser

```
Step 1: Open a file whose language has no parser installed (or isn't supported).
  Step 2: Press `o` or type a closing character.
  Indentation behaves exactly as it did before this feature existed — Neovim's normal generic indenting, with no error or visible glitch.
```

## 6 — Reindenting existing lines

```
Step 1: Select or move over lines whose indentation is currently wrong, and trigger Neovim's normal reindent action.
  Step 2: The affected lines are recomputed the same way new lines are — using the buffer's real nesting, not the generic fallback.
```

---

# Behavior Rules

- Applies to every filetype that has a parser available, not just one language — no per-language setup should be required beyond having the parser.
- Falls back cleanly to Neovim's standard indentation when no parser (or no structure information) is available for the buffer — never breaks or blocks editing.
- Only changes indentation logic; it does not change highlighting, folding, or visual indent guides, which already work today.
- Should stay correct as parsers/structure definitions update — it shouldn't need hand-maintenance per language to keep working.

---

# Success Criteria

- [ ] Opening a new line inside a nested tag/block indents one level deeper than the line that opened it, matching existing sibling content.
- [ ] Typing a closing character dedents the line to match its opening line.
- [ ] Deeply nested structures accumulate the correct total depth, not just one level.
- [ ] Blank lines and comments get a sensible indent rather than fighting the writer.
- [ ] Filetypes without a parser keep behaving exactly as they do today.
- [ ] Reindenting existing lines produces the same result as typing them fresh would.

---

# Out of Scope

- Whole-buffer or LSP-driven formatting (`gq`, formatter integrations) — this spec only covers the line-by-line indent decision, not a formatting pass.
- Visual indent guides — already covered by the existing indent-guide feature.
- Per-construct configuration of indent width beyond the buffer's normal shift width setting.
