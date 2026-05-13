---
name: tec-dev-spec
description: "Generate a dev spec (implementation blueprint) for BeastVim from a feature request or problem statement. Use when asked to 'dev spec', 'implementation plan', 'break down this feature', 'plan implementation', 'how to implement this'."
---

# Dev Spec — BeastVim

Generate a detailed implementation blueprint for a BeastVim feature. The output is a markdown file at `docs/dev-specs/<feature-name>.md` that `/tec-implement` can pick up phase by phase.

This is a personal Neovim config — there is no PM, no work-item tracker, no team assignment. The "spec" is a paragraph or two describing what you want to build (e.g. "I want a unified palette that all libs read from"). The skill turns that into a structured plan.

## Input

The user provides a feature request — a paragraph, a sketch, a linked snippet, or just a sentence (e.g. *"opt-in result caching for statusline components"*).

If no input is given, ask: "What are we planning?" Don't proceed with a guess.

## Step 1: Ensure Codemaps Exist

Check if `docs/CODEMAPS/INDEX.md` exists:

- **Yes** → read the relevant codemap files for the area being touched (e.g. for a statusline change, read `docs/CODEMAPS/backend.md` or whichever maps the bar)
- **No** → run `/tec-update-codemaps` first, then read the result

A dev spec written without codemaps is guesswork. The codemap is what lets the spec name **actual file paths** instead of placeholders.

## Step 2: Analyze the Feature Request

Extract:

- **Goal** — what are we building, in one sentence
- **Requirements** — bullet list of the concrete behaviours needed
- **Success criteria** — how do we know it's done (a bench number, a `:checkhealth` clean, a manual repro)
- **Out of scope** — what we are explicitly NOT building (the spec stays small)

If any of these is missing or ambiguous, **ask one focused question per ambiguity** before writing the spec. Vague specs produce phase plans that drift.

## Step 3: Research Before Building (MANDATORY)

The dev spec **must** contain a `## Research` section with real findings. Skipping this step produces dev specs that reinvent something already in the repo.

### 3a — Search the Repo

```bash
git grep -niE '<keyword-1>|<keyword-2>'
```

For BeastVim, also check:

- `lua/beast/util/init.lua` — shared helpers (e.g. `Util.scratch_buf`, `Util.wo`, `Util.colors.inspect`)
- `lua/beast/libs/view.lua` — shared `View` base class (any new buf+win UI must subclass this)
- `lua/beast/libs/<adjacent-lib>/` — adjacent libs often have the pattern you want
- `AGENTS.md` § *Shared Modules Registry* and § *Known DRY Opportunities* — the registry lists what's already shared; the DRY-opportunities table flags patterns that are about to be extracted

If the functionality already exists, **reuse it**. Treat the AGENTS DRY-opportunities table as a list of patterns that are *already known* to need extracting — if your dev spec is the third instance of one, the spec must include "extract first" as a Phase.

### 3b — Search for Packages

For BeastVim this is rare, but check:

- Neovim ecosystem (a dedicated plugin like `nvim-treesitter`, etc.) for things outside core
- Native Neovim API (`vim.api.*`, `vim.fn.*`, `vim.uv.*`, `vim.schedule_wrap`, `vim.system`) — almost always the right answer, given the project conventions in `AGENTS.md`

Avoid pulling in a plugin when a native API does it. The AGENTS file is explicit about preferring native primitives.

### 3c — Decide and Document

| Signal | Action |
|---|---|
| Pattern exists in repo, reusable as-is | **Adopt** — `require` it from the dev spec's new file |
| Pattern exists but is single-use, would benefit from extraction | **Extract first** — Phase 1 is the extraction, then the new feature uses the extracted module |
| Native Neovim API does it directly | **Use native** — name the API in the Research section |
| Nothing suitable | **Build** — write custom, *informed* by the research above |

### 3d — Required Research Section Format

```markdown
## Research

### Repo Search
- Searched for: [keywords / patterns]
- Found: [files + symbols, or "No existing code covers this"]
- Reuse opportunity: [Adopt / Extract first / None — what to do]

### Package Search
- Searched: [Neovim ecosystem / native API / specific plugins]
- Found: [API name + relevance, or plugin + license]
- Decision: **Adopt** / **Extract first** / **Use native** / **Build** — [reason]
```

If the Research section is missing, says only "N/A", or shows no actual searches were run, the dev spec is invalid and **must not** proceed to implementation.

## Step 4: Generate the Dev Spec

Match the shape of existing dev specs in `docs/dev-specs/` (read one — `beast-palette.md` and `statusline-library.md` are good references). The skeleton:

```markdown
# Dev Spec: <Feature Name>

## Summary
[2–3 sentences: what we're building and the approach. Reference the existing pattern being adopted/extended/replaced.]

## Requirements
- [Concrete behaviour 1]
- [Concrete behaviour 2]
- [Out of scope is explicit, not implied]

## Research
[Per Step 3d — actual searches, real findings.]

## Architecture Changes

| File | Action | Purpose |
|------|--------|---------|
| `lua/beast/.../<file>.lua` | Create / Modify / Delete | [why] |

## Implementation Phases

### Phase 1: [Name] — [Goal of this phase]
1. **[Step]** (File: `lua/beast/.../<file>.lua`)
   - Action: [Specific edit — function name, what it does]
   - Why: [Reason — connects back to a Requirement]
   - Depends on: None / Step N
   - Risk: Low / Medium / High

### Phase 2: [Name] — [Goal]
...

## Testing Strategy
- Unit tests: [what to add under `tests/` — note if `tests/` is currently empty, this is also a process gap fix]
- Bench: [if a hot path is touched, name the `scripts/bench-<lib>.lua` to add or update]
- Manual verification: [exact steps — open file X, trigger Y, see Z]

## Risks & Mitigations
- **Risk**: [Description] → **Mitigation**: [How to handle]

## Success Criteria
- [ ] [Concrete pass condition — e.g. "bench-statusline.lua reports < 15 µs/render"]
- [ ] [`:checkhealth` clean for the lib]
- [ ] [Codemap regenerated and committed alongside]
```

### Rules for the Dev Spec

- **Exact file paths** — use real paths from the codebase, not placeholders. The codemap is how you find them.
- **Independent phases** — each phase should land on `main` independently and leave the project in a working state. No phase exists only to set up a later phase that breaks things in between.
- **Smallest first** — Phase 1 is the **minimum viable slice** that can be merged. If a feature can ship in one phase, do that — don't invent phases.
- **Follow existing patterns** — the AGENTS file (`File Structure`, `Type Naming`, `The View Pattern`, `Component Tables vs Classes`, `Config Pattern`) is the architectural contract. Spec changes that violate it must be flagged for ADR review (Step 5 below).
- **Bench thresholds in Success Criteria** — if a hot path is touched, the success criterion is a number (`< 15 µs/render`), not "feels fast".
- **No code yet** — this step produces only the plan.

## Step 5: ADR Check

Does the dev spec involve an architectural decision? Check:

- New `View` subclass or new buf+win component?
- New shared module (something other libs will require)?
- New animation, namespace, or autocmd lifecycle?
- Change in a pattern from the AGENTS file (e.g. moving from "table of functions" to "class")?
- Switch from a vendored plugin to native, or vice versa (see ADR-009)?
- Reintroduction or removal of a shape previously covered by an ADR (see ADR-010 → ADR-013)?

If **yes** to any, append:

```markdown
## ADR Required

This dev spec involves architectural decision(s) that must be documented as ADRs once committed:

- [Decision description]
- [Reference to existing ADR being superseded, if any]
```

Do **NOT** create the ADR file during dev-spec generation — the spec may be exploratory. ADRs are created during `/tec-implement`'s wrap-up step, when the decision is committed to code (going-forward mode of `/tec-adr`).

## Step 6: Save the Dev Spec

Save as `docs/dev-specs/<feature-name>.md`. Use kebab-case derived from the feature name — match the convention of the existing files (`beast-palette.md`, `statusline-library.md`, `packer-early-colorscheme.md`).

Then tell the user:

> Dev spec saved to `docs/dev-specs/<file>.md`. Review it. Reply `proceed` to start `/tec-implement` on Phase 1, or tell me what to change.

**STOP** and wait. Do not start implementation in the same turn. The user often refines the spec before approving.

## Step 7: Iterate on the Spec

If the user says:

- `modify: <changes>` → edit the file, show the diff, ask again.
- `skip phase X` → remove that phase, renumber the remainder.
- `add <thing>` → incorporate into the right phase (or a new one), ask if the addition needs its own ADR Required line.
- `proceed` / `yes` / `looks good` → tell the user to run `/tec-implement docs/dev-specs/<file>.md`. The dev spec skill is **done at this point** — handing off to `/tec-implement` is the contract.

## Tips

- Keep Phase 1 to **1–3 files max** — the smallest deliverable slice. If Phase 1 needs more, the spec is too big and should be split into multiple specs.
- A dev spec for a hot-path change is incomplete without a `bench-<lib>.lua` plan in Testing Strategy. If the lib has no bench yet, the spec adds one.
- If the feature touches more than 5 files, consider whether two smaller specs would be cleaner. Easier review, easier rollback.
- Reference specific sections of `AGENTS.md` (e.g. *§ The View Pattern*, *§ Config Pattern*) when explaining architecture changes — so the reader doesn't have to guess which convention you're following.
- Reference specific lines from the codemap when describing where a new module fits in the require graph.
