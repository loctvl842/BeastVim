---
name: pm-spec
description: "Generate a product spec (UI/UX design, behavior, scenarios) for a feature. Use when asked to 'pm spec', 'product spec', 'design the feature', 'write a spec', 'what should this look like', 'UX for'."
---

# PM Spec

Generate a product spec that describes what a feature looks, feels, and behaves like — from the user's perspective. No implementation details.

## Input

The user provides a feature idea — either as text, a rough description, or a reference to existing behavior. If the description is too vague to spec, ask one focused question to unblock.

## Step 1: Read Existing Context

Before designing:
- Read `docs/CODEMAP/INDEX.md` — understand what already exists so the spec doesn't redesign something that's there
- Skim `docs/pm-specs/` if it exists — check for related or superseded specs

## Step 2: Generate the PM Spec

Produce a structured spec with this format:

> **Note:** The template below is indented for readability inside this code fence. When generating the actual file, write all content at the root level — no leading spaces.

`````markdown
    ---
    name: [feature-name]
    description: [one-line feature summary]
    generated: YYYY-mm-dd
    ---

    # Summary
    [1-2 sentences: what this feature does and why it exists]

    ---

    # Problem

    [What frustrates the user today? Describe the gap concretely — what they have to do now, what breaks or feels wrong. No jargon. Write so someone who has never opened Neovim understands the pain.]

    ## Why now
    [Why does this need to exist? What gets unlocked or unblocked?]

    ---

    # Target Behavior

    [ASCII diagram(s) of the end state. Show exactly what the user sees on screen — buffer content, floating windows, highlights, statusline, etc. Use concrete text, not labels like "item list here".]

    ```
    ┌─────────────────────────────────────────┐
    │  [exact UI content]                     │
    │  [second line]                          │
    └─────────────────────────────────────────┘
    ```

    Use multiple STATE blocks when the UI has distinct modes:

    ```
    STATE 1 — [label]:
      [what the user sees]

    ─────────────────────────────────────────
    STATE 2 — [label]:
      [what the user sees]
    ```

    ---

    # Scenarios

    Walk through every meaningful case step by step. Each scenario must be numbered and titled. Cover: the happy path, at least one edge case, and any cancellation/error path.

    ## 1 — [Scenario name]

    ```
    Step 1: [what the user does]
      [what they see]

    Step 2: [what they do next]
      [what they see]

    Step 3: [outcome]
      [what they see]
    ```

    ## 2 — [Scenario name]
    ...

    ---

    # Behavior Rules

    Bullet list of specific rules that aren't obvious from the scenarios:
    - [Rule 1]
    - [Rule 2]

    ---

    # Success Criteria

    What the user experiences when the feature is done correctly:
    - [ ] [Observable outcome 1]
    - [ ] [Observable outcome 2]

    ---

    # Out of Scope

    - [Thing not included — and why deferred]
    - [Another thing]
`````

### Rules for the PM Spec

- **User language only** — no file paths, function names, module names, or implementation words
- **Show, don't describe** — every UI claim needs an ASCII diagram to back it up
- **Scenarios are mandatory** — at least one happy path and one edge/error case
- **No code yet** — this step produces only design, not architecture
- **Metadata header is mandatory** — include `name`, `description`, and `generated` at the top; set `generated` to the current date when the spec is created

## Step 3: Save the PM Spec

Save the spec at `docs/pm-specs/<feature-name>.md` (create the directory if needed). Use a kebab-case filename (e.g., `docs/pm-specs/key-hint-popup.md`).

## Step 4: Wait for Confirmation

Tell the user the PM spec has been saved and **STOP**. Do not proceed until the user confirms.

If the user wants changes:
- "modify: [changes]" → update the spec file
- "add scenario: [description]" → add a new scenario
- "simplify" → trim to the essential happy path

## Tips

- If the feature has no visible UI (e.g., a performance improvement), the Target Behavior section shows the *result* the user notices, not the internal change
- One spec per feature — if two features share a spec they'll likely conflict in the dev phase
- The scenarios here become the manual verification checklist in the dev spec
