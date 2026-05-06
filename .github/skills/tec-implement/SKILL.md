---
name: tec-implement
description: "Implement a dev spec task by task. Picks up from a saved dev spec file and works through phases in order — implement, verify, commit. Use when asked to 'implement', 'start building', 'execute dev spec', 'work on tasks', 'pick up task', 'start phase'."
---

# Implement Dev Spec

Execute a dev spec by working through tasks phase by phase. Each task: implement → verify → commit.

## Input

The user provides:
- **Dev spec file path** (e.g., `docs/dev-specs/add-user-auth.md`) — required
- **Specific task or phase** (optional — defaults to the next incomplete task)

If no dev spec path is given, check `docs/dev-specs/` for recent files and ask which one to implement.

## Step 1: Load the Dev Spec

Read the dev spec file. Extract:
- Implementation phases and tasks
- Success criteria (these become the verification gate at the end of each phase)
- Any `## ADR Required` section (handled in Step 6 — wrap-up)

## Step 2: Read Codemaps

Read `docs/CODEMAPS/INDEX.md` if it exists — orient yourself before touching code.

## Step 3: Review Anti-Rationalizations

Read the `anti-rationalization` instruction before starting. Don't skip steps.

## Step 4: Execute Tasks

Work through tasks **in phase order, by priority**:

For each task:
1. **Announce** — "Starting Task #N: [title]"
2. **Search first** — Check the repo for existing code that solves this before writing new code
3. **Implement** — Make the changes described in the task
4. **Review** — Invoke the `tec-review` agent to validate the implementation against the dev spec. Check for spec alignment, minimality, pattern compliance, and correctness.
   - If **PASS** → continue
   - If **FAIL** → fix the blocking issues before proceeding
5. **Simplify** — Check the code just written against the `tec-simplify` rules: deep nesting (3+), long functions (50+), generic names, dead code, over-engineering. Fix any issues before moving on. This is automatic — don't ask the user.
6. **Verify** — Run the relevant local checks. For BeastVim that means:
   - `luacheck lua/` from the repo root if any Lua files changed
   - `stylua --check lua/` if `stylua` is installed
   - `nvim --clean --headless -l scripts/bench-<lib>.lua` if the task touched a lib that has a bench
   - Any phase-specific manual repro listed in the dev spec's *Testing Strategy* section
7. **Commit** — Stage and describe what was done. Use the task title as the commit message prefix.

### Rules
- **Never skip to the next phase** until all tasks in the current phase are done and verified
- **One task at a time** — don't batch multiple tasks into one change
- **If a task is blocked**, tell the user and move to the next unblocked task in the same phase
- **If you discover something not in the spec**, flag it to the user — don't scope-creep

## Step 5: Phase Checkpoint

After completing all tasks in a phase:
1. Confirm with the user: "Phase N complete. [summary]. Ready for Phase N+1?"
2. Wait for confirmation before proceeding
3. If the user says "stop" — save progress notes to the dev spec file

## Step 6: Wrap Up

After all phases are complete:
1. Run the `tec-update-codemaps` skill to regenerate `docs/CODEMAPS/` — implementation likely changed the architecture
2. Check the dev spec for an `## ADR Required` section — if present, create the ADR(s) now using the `tec-adr` format and save to `docs/ADRs/`. Use these sources for maximum accuracy:
   - **Dev spec** → Context, Decision, Rationale sections
   - **Search-first results** (Step 4.1) → Alternatives Considered (real packages/patterns evaluated, not fabricated)
   - **Code changes just made** → Evidence (exact files changed, patterns used)
   - **tec-review feedback** → Consequences (what the review caught, tradeoffs accepted)
   - **Codemaps diff** → how architecture changed before vs after
3. Update the dev spec file — mark tasks as done, add a "## Completed" timestamp
4. Stage everything: `git add docs/CODEMAPS/ docs/dev-specs/ docs/ADRs/`
5. Tell the user the implementation is complete and ready for commit

## Tips

- If a task takes longer than estimated, note the actual time in the dev spec for future calibration
- Don't refactor surrounding code — only change what the task specifies
- If tests fail after a change, fix them before moving to the next task
