---
name: dev-spec
description: "Generate a dev spec (implementation blueprint) from a PM spec. Use when asked to 'dev spec', 'implementation plan', 'break down this spec', 'plan implementation', 'how to implement this', 'dev plan from spec'."
---

# Dev Spec

Generate a detailed implementation blueprint from an existing PM spec.

## Input

The user provides a PM spec file path (e.g., `docs/pm-specs/key-hint-popup.md`). If no PM spec is provided, ask for one — or suggest running `/pm-spec` first.

## Step 1: Read the PM Spec

Read the PM spec in full. Extract:
- **Goal** — What are we building and why?
- **Behavior rules** — What must the implementation honour?
- **Success criteria** — The user-facing outcomes that define "done"
- **Out of scope** — What are we NOT building?

The PM spec is the source of truth. If anything in the PM spec is ambiguous or contradicts a known technical constraint, flag it before proceeding.

## Step 2: Read the Codemap

Check if `docs/CODEMAP/INDEX.md` exists:
- **If yes** → read the relevant codemap files to understand the existing architecture
- **If no** → run the `update-codemap` skill first to generate them, then read the results

## Step 3: Research Before Building (MANDATORY)

Before writing the dev spec, search for existing solutions. Don't reinvent the wheel.

**This step is NOT optional.** You MUST perform the searches below and include a `## Research` section in the dev spec with your findings. If you skip this step, the dev spec is incomplete and must not proceed to implementation.

### 3a: Search the Repo
- Grep for related function names, module names, keywords
- Check `lua/beast/util/`, `lua/beast/libs/` for existing utilities
- Check test files (`tests/test-*.lua`) and bench scripts (`scripts/bench-*.lua`) — they reveal existing patterns
- **Log what you searched for and what you found** (even if nothing)

If the functionality already exists, **reuse it**.

### 3b: Check Built-ins and Existing Libs

BeastVim is a pure-Lua Neovim config — there is no package manager to install from. Before building, check:

| Source | Where to look |
|---|---|
| Neovim built-in APIs | `vim.api`, `vim.fn`, `vim.ui`, `vim.lsp`, `vim.treesitter` |
| Existing beast libs | `lua/beast/libs/` — animate, view, util, etc. |
| Lua standard library | `string`, `table`, `math`, `io` |

### 3c: Decide and Document
| Signal | Action |
|---|---|
| Built-in Neovim API covers it | **Use** — no new code needed |
| Existing beast lib covers it | **Reuse** — call or extend the existing module |
| Nothing suitable | **Build** — write custom, informed by research |

### 3d: Required Research Section Format
The dev spec MUST include this section with actual search results:

```markdown
## Research

### Repo Search
- Searched for: [keywords/patterns you grepped]
- Found: [what you found, or "No existing code covers this"]
- Reuse opportunity: [Yes/No — what to reuse]

### Built-in / Existing Lib Check
- Checked: [Neovim APIs or beast libs evaluated]
- Found: [what applies, or "Nothing suitable"]
- Decision: **Use** / **Reuse** / **Build** — [reason]
```

## Step 4: Generate the Dev Spec

Produce a structured dev spec with this format:

> **Note:** The template below is indented for readability inside this code fence. When generating the actual file, write all content at the root level — no leading spaces.

```markdown
    ---
    name: [feature-name]
    description: [one-line implementation summary]
    generated: YYYY-mm-dd
    ---

    > PM Spec: [docs/pm-specs/<feature-name>.md](../pm-specs/<feature-name>.md)

    # Summary
    [2-3 sentences: what we're building and the implementation approach]

    ---

    # Context

    ## Problem
    [One paragraph — the technical gap that needs to be filled. Derived from the PM spec but framed for an engineer: what module is missing, what behaviour is unimplemented, what the code lacks.]

    ### Solution
    [What will the codebase look like after this change? One short paragraph — no code yet.]

    ---

    # Research
    [From Step 3 — actual search results, not placeholders]

    ---

    # Architecture Changes
    - [New/modified file: path — what and why]
    - [New/modified file: path — what and why]

    ## Implementation Phases

    ## Phase 1: [Name] — [Goal of this phase]
    1. **[Step]** (File: path/to/file)
       - Action: [Specific action]
       - Why: [Reason]
       - Depends on: None / Step N
       - Risk: Low/Medium/High

    2. **[Step]** (File: path/to/file)
       ...

    ## Phase 2: [Name] — [Goal]
    ...

    # Testing Strategy
    - Headless tests: [which `tests/test-*.lua` to run or write]
    - Bench: [which `scripts/bench-*.lua` to run if a hot-path lib was touched]
    - Manual: [reference the scenarios in the PM spec — what to open in nvim and verify]

    # Success Criteria
    [Copy from the PM spec's success criteria, adding any technical gates]
    - [ ] Criterion 1
    - [ ] Criterion 2
```

### Rules for the Dev Spec

- **Exact file paths** — Use real paths from the codebase, not placeholders.
- **Independent phases** — Each phase should be mergeable on its own.
- **Smallest first** — Phase 1 is the minimum viable slice.
- **Follow existing patterns** — Use the project's conventions (from codemap and codebase).
- **No code yet** — This step produces only the plan.
- **Always link the PM spec** — The `> PM Spec:` line at the top is mandatory.
- **Metadata header is mandatory** — include `name`, `description`, and `generated` at the top; set `generated` to the current date when the spec is created.

## Step 5: Save the Dev Spec

Save the dev spec at `docs/dev-specs/<feature-name>.md`. Use the same kebab-case name as the PM spec (e.g., `docs/dev-specs/key-hint-popup.md`).

## Step 6: Wait for Confirmation

Tell the user the dev spec has been saved and **STOP**. Do not proceed until the user confirms with "yes", "proceed", "go ahead", or similar.

If the user wants changes:
- "modify: [changes]" → update the dev spec file
- "skip phase X" → remove that phase
- "add [thing]" → incorporate it

## Tips

- Keep Phase 1 to 1-3 files max — smallest deliverable slice
- Flag any PM spec gaps early (don't assume, ask)
- If the feature touches >5 files, consider splitting into multiple dev specs
- The PM spec's scenarios are the manual verification guide — reference them in Testing Strategy rather than duplicating them
