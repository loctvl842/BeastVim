---
name: xml-init
description: XML language support so fold signs and the active-block line follow the real element structure
generated: 2026-11-22
---

# Summary
XML files get proper language support: fold signs sit only on the lines that open a multi-line element, the vertical line that marks the current element is drawn on every line that belongs to it even when the file's indentation is uneven, and typing the `>` of an opening tag writes the closing tag for you.

---

# Problem

Open an XML file today and BeastVim treats it as plain indented text. It has no idea what an element is. Two things go wrong:

- **Fold signs land on the wrong lines.** A fold sign should appear where an element opens. Instead it appears on whichever line happens to be indented deeper than the one above, so the sign sits on the first line inside an element rather than on its opening tag, a line of plain text gets a sign, and one stray line with different indentation chops a single element into several unrelated folds.
- **The current-element line has holes.** With the cursor inside an element, the vertical line should run along the whole element. Instead it is drawn only on the few lines around the cursor and stops at the first line whose indentation differs, so the rest of the element has no line.

Real-world XML is often indented unevenly (mixed content, pasted snippets, text next to tags), so this is the common case, not a rare one.

- **Every element is typed twice.** Writing `<class>` means also typing `</class>` by hand, and forgetting it leaves the file broken.

## Why now
Every other language BeastVim ships with (JSON, Markdown, TypeScript, Python, C++) has its own small language plugin. XML is the odd one out, and `complex.xml` shows the gap on the first screen. A language plugin is also the place that makes folds and the element line correct for XML without special-casing them in the editor core.

---

# Target Behavior

`complex.xml`, cursor on line 34, column 12. Line 35 is indented less than its neighbours, which is what breaks the indent-based guesses.

STATE 1 — Today (indent guesses):

```
 fold  line
        32    <app:annotations>       ← no sign on the line that opens it
  ▾     33      <app:annotation key="multiline">
  ▾     34        First line            ← sign on a text line (wrong)
        35    <app:code>literal …</app:code>
  ▾     36        Final line            ← sign on a text line (wrong)
        37      </app:annotation>
        38    </app:annotations>

 current-element line (column 6):
        33      <app:annotation key="multiline">
        34      ▏ First line            ← only this line
        35    <app:code>literal …</app:code>
        36        Final line            ← missing
        37      </app:annotation>
```

STATE 2 — With XML support:

```
 fold  line
  ▾     32    <app:annotations>
  ▾     33      <app:annotation key="multiline">
        34        First line
        35    <app:code>literal …</app:code>
        36        Final line
        37      </app:annotation>
        38    </app:annotations>

 current-element line (column 6):
        33      <app:annotation key="multiline">
        34      ▏ First line            ← drawn
        35    <app:code>literal …</app:code>   ← none: this text sits left of the line
        36      ▏ Final line            ← drawn
        37      </app:annotation>
```

Fold signs appear on lines 32 and 33 only. Both are elements that open on one line and close on a later one.

STATE 3 — Folded (`zc` on line 33):

```
  ▾     32    <app:annotations>
  ▸     33      <app:annotation key="multiline">
        37      </app:annotation>
        38    </app:annotations>
```

The sign on 33 flips to the closed form and the lines inside (34 to 36) disappear, including their element line. The opening and the closing tag both stay on screen, so a folded element still reads as a complete pair.

STATE 4 — Auto-close tag (`|` is the cursor):

```
Before pressing >:        <class|
After pressing >:         <class>|</class>

With attributes:          <app:label key="team"|
After pressing >:         <app:label key="team">|</app:label>
```

The cursor stays between the two tags, ready to type the content.

---

# Scenarios

## 1 — Open an XML file

```
Step 1: Open complex.xml.
  Tags, attributes, text and comments are coloured.

Step 2: Look at the fold column.
  A sign sits on every line where a multi-line element opens
  (<app:metadata>, <app:labels>, <app:annotations>, ...).
  Lines of text and single-line elements such as
  <app:label key="team">platform</app:label> have no sign.
```

## 2 — Cursor inside an element with uneven indentation (the reported case)

```
Step 1: Put the cursor on line 34, column 12 (inside "First line").
  The element line is drawn at column 6 on line 34.

Step 2: Look at the rest of the element.
  The line is also drawn on line 36 ("Final line").
  Line 35 has no line, because its text starts left of column 6.

Step 3: Look at the closing tag on line 37.
  No line crosses it; the element is over.
```

## 3 — Cursor on a single-line element

```
Step 1: Move the cursor onto line 35, on <app:code>.
  That element opens and closes on one line, so it has no body to mark.

Step 2: Look at the element line.
  The enclosing element (<app:annotation>, lines 33 to 37) is marked instead,
  exactly as in scenario 2.
```

## 4 — Cursor on the opening or closing tag

```
Step 1: Move the cursor onto line 33 (the opening tag), then onto line 37 (the closing tag).
  In both cases the element line marks the same element,
  <app:annotation>, so the mark does not jump while moving along its edges.
```

## 5 — Fold and unfold

```
Step 1: On line 33 press zc.
  Everything between the tags collapses. Line 33 (opening tag, closed sign)
  and line 37 (</app:annotation>) stay visible, one above the other.

Step 2: Press zo.
  The element expands and the sign shows the open form again.

Step 3: Press zc on line 34 (inside the element).
  The whole <app:annotation> body collapses, not just one text line.

Step 4: Press zc on an element whose opening and closing tag are on neighbouring lines,
  or on a one-line element.
  There is nothing between the tags to hide, so that element does not fold on its own;
  zc closes the enclosing element instead.
```

## 6 — First time on a machine

```
Step 1: Open an XML file on a machine that has never opened one.
  The file shows at once and is editable. Folds and the element line
  behave as they do today (indent based).

Step 2: Wait a few seconds while XML support is fetched.
  Colours, folds and the element line switch to the correct behaviour
  on their own. No need to reopen the file.

Step 3: Open another XML file.
  Correct from the first frame.
```

## 7 — Broken XML (error case)

```
Step 1: Delete a closing tag so an element never ends.
  The editor does not freeze or print errors.

Step 2: Look at folds and the element line.
  Complete elements around the problem still fold and mark correctly.
  The broken element falls back to its best guess, or shows nothing.

Step 3: Put the closing tag back.
  Everything returns to normal.
```

## 8 — Auto-close tag

```
Step 1: In insert mode, type <class
  Nothing extra appears yet.

Step 2: Press >
  The text reads <class></class> and the cursor sits between the tags.

Step 3: Type the content.
  <class>hello|</class>

Step 4: Nested: on a new line type <item and press >
  Each element closes itself; the outer one is untouched.
```

## 9 — Cases where nothing is added

```
Step 1: Type <br/ and press >
  A self-closing tag is already complete. Result: <br/>

Step 2: Type </class and press >
  A closing tag never gets a partner. Result: </class>

Step 3: Type <!-- , <?xml version="1.0"?  or <!DOCTYPE note  and press >
  Comments, declarations and doctypes never get a partner.

Step 4: Type <a href="x>y"  (the > is inside the quotes) and press >
  The first > is part of the attribute value, so nothing is added there.
  Only the > that really ends the tag closes it.

Step 5: Type a < b in text (a space after <) and press >
  It is not a tag, so nothing is added.

Step 6: Put the cursor in <class|</class> where the closing tag already exists and press >
  No second closing tag is added.
```

---

# Behavior Rules

- A fold sign appears only on the opening tag line of an element that has at least one line between its tags.
- A fold always covers everything between one element's tags, never a slice of its text. The opening and closing tag lines are never hidden by that element's own fold.
- The element line is drawn at the indentation of the opening tag, so uneven body text never moves it.
- The element line is drawn on each stretch of the body that is indented at least as deep as the first body line. A shallower line breaks the stretch and gets no line. Two stretches in the same element are both drawn.
- A blank line inside a stretch does not break it.
- Cursor on a single-line element: the nearest enclosing multi-line element is marked.
- Cursor on an opening tag, a closing tag or anywhere in the body marks the same element.
- Nested elements: the innermost multi-line element around the cursor is the one marked.
- Auto-close fires only when `>` is typed (not on paste), only for an opening tag, and the closing tag uses the exact name, prefix included (`app:label`).
- After auto-close the cursor sits between the tags, so one undo removes both the `>` and the added closing tag.
- Files with a different extension that are still XML (schemas, stylesheets, SVG) are out of the first cut.
- The plugin only works inside BeastVim and tells the user plainly when it is loaded elsewhere.

---

# Success Criteria

- [ ] In `complex.xml`, no fold sign appears on lines 34, 35 or 36.
- [ ] Fold signs appear on 32 and 33, and on every other multi-line element.
- [ ] Cursor at line 34, column 12 draws the element line on line 34 and on line 36, and not on line 35.
- [ ] The scope report for that cursor position lists two stretches, 34 to 34 and 36 to 36, both at column 6 with body indent 8.
- [ ] Cursor on single-line element (line 35) marks the enclosing element.
- [ ] `zc` on any line inside an element folds everything between its tags and leaves both the opening and the closing tag visible.
- [ ] First open on a clean machine works without a restart once support has been fetched.
- [ ] A file with a missing closing tag opens without errors.
- [ ] Typing `<class` then `>` gives `<class>|</class>` with the cursor between the tags.
- [ ] `<app:label key="team"` then `>` closes with `</app:label>`.
- [ ] Self-closing tags, closing tags, comments, declarations, doctypes and a `>` inside quotes add nothing.
- [ ] One undo reverts the `>` and the added closing tag together.
- [ ] No regression for the other languages' fold signs and element line.

---

# Out of Scope

- A language server for XML (diagnostics, completion, hover, schema validation). Deferred: the reported problems do not need one, and it adds a download and settings to decide.
- Formatting on save. Deferred with the language server.
- XSD, XSLT, SVG and other XML dialects with their own file types.
- Tag renaming (editing an opening tag does not rename its closing tag). Deferred: separate from the reported problems.
- Pressing Enter between the tags to open an indented body line. Deferred: not asked for.
- Changes to how other languages draw folds or the element line.
