---
name: tec-adr
description: "Generate Architecture Decision Records for BeastVim from git history, dev specs, code patterns, and (optionally) GitHub PRs. Captures the WHY behind decisions. Use when asked to 'generate ADRs', 'document decisions', 'why was this built this way', 'create ADR'."
---

# Architecture Decision Records (ADR) Generator — BeastVim

Generate ADRs by scanning **git history, dev specs, code comments, and merge patterns** — capturing the WHY behind each decision in a personal Neovim config.

This is **not** a corporate ADO/wiki workflow. The evidence sources are local (git, `docs/dev-specs/`, code) plus optional GitHub PR enrichment via `gh`. Existing ADRs live at `docs/ADRs/` and follow the format already established by ADR-001 through the latest entry — read one of those before generating new ones.

## Input

The user provides:

- **Scope** — `"all"` for a retroactive sweep, or a specific area (`"statusline"`, `"profile"`, `"the namespaced highlight rework"`).
- **Mode** (optional) — *retroactive* (sweep history for past decisions) or *going-forward* (capture a single decision being made now). Defaults to retroactive.

If only "generate ADRs" is given with no scope, ask which.

## Step 1: Read Existing Context

In this order:

1. `docs/ADRs/INDEX.md` — list the existing ADR titles only. **Do not re-read each ADR file** unless you need to confirm a "Superseded by" relationship — that's the one case where the body matters before generating.
2. `docs/CODEMAPS/INDEX.md` — current architecture overview.
3. `docs/dev-specs/*.md` — every dev spec is a documented decision. Skim titles + `## Summary` of each. A dev spec whose phases all landed but has no matching ADR is the **highest-value gap** to fill.
4. The most recent ADR file (`docs/ADRs/0NN-*.md` with the highest number) — **format reference**. Match its header order, status conventions, and Evidence-line shape exactly. ADRs in this repo are not free-form.

## Step 2: Scan Git History (primary source)

Scan only the default branch (`git log main` — or whatever `git branch --show-current` reports as the integration branch). **Do not use `--all`** — unmerged feature branches contain abandoned experiments that should not become ADRs.

### 2a — Decision-shaped commits

```bash
git log --oneline main | grep -iE 'feat|refactor|migrate|replace|remove|introduce|switch'
```

Look for verbs that signal an architectural change: *introduce*, *switch from X to Y*, *replace X with Y*, *extract*, *deprecate*, *promote to shared*. Cosmetic refactors (rename, extract helper) are **not** ADR-worthy unless the rename signalled a model change (see ADR-006 for the bar).

### 2b — Structural diffs

For each candidate commit, check if it touched architecture:

- New top-level directory under `lua/beast/libs/` or `lua/beast/plugins/`
- Rename of a module that other modules require (the require-graph shape changed)
- Addition or removal of a shared module (e.g. `lua/beast/libs/animate.lua`)
- New `:autocmd`-loaded file or new `init.lua` boundary

### 2c — Decision-rationale comments

Grep the affected files for explicit rationale comments:

```bash
git grep -nE -- '-- (NOTE|WHY|DESIGN|RATIONALE|HACK|IMPORTANT):'
```

A function with a `-- WHY:` comment is almost always paired with an architectural choice (caching shape, async boundary, namespace lifecycle). Cross-reference the comment with the introducing commit to find the decision.

### 2d — Code-pattern signals

These are recurring shapes that, when newly introduced, are decisions:

| Pattern | What it signals |
|---|---|
| New `View` subclass via `View:extend(...)` | A new buf+win component (decision: how it composes with existing libs) |
| New `setmetatable(M, { __index = ..., __newindex = ... })` proxy | Read-only-config decision (see ADR-003) |
| New `vim.api.nvim_create_namespace("beast.<lib>.<purpose>")` | Highlight-namespace decision (see ADR-008) |
| New `scripts/bench-<lib>.lua` | Run-time-perf contract decision |
| New `package.loaded["beast.libs.<x>.highlights"] = nil` reset | ColorScheme reload decision |
| Switch from a vendored plugin (e.g. heirline) to native (e.g. `%!`) | See ADR-009 — these are always ADR-worthy |

## Step 3: Enrich from GitHub PRs (optional)

If the user has merged via GitHub PRs (check: any commit message matching `Merge pull request #\d+`):

```bash
gh pr list --state merged --limit 50 --json number,title,body,url
```

For PRs with `body` longer than ~200 chars or that link to a dev spec, extract:

- **Decision rationale** from the PR description
- **Alternatives considered** from review threads (`gh pr view <num> --comments`)
- **Trade-offs accepted** from review back-and-forth

If `gh` is not installed or the user works directly on `main` without PRs, **skip this step entirely** — git-based ADRs are sufficient. **Do not invent PR-style debate that never happened.**

## Step 4: Cross-Reference Dev Specs

For each candidate decision identified in Steps 2–3, check if a dev spec already documents it:

```bash
grep -lriE '<decision-keyword>' docs/dev-specs/
```

If a matching dev spec exists, the dev spec's:

- `## Summary` → ADR `## Context`
- `## Architecture Changes` → ADR `## Decision`
- `## Risks & Mitigations` → ADR `## Consequences`

This is the **highest-fidelity** path. A dev spec that landed without a matching ADR is the cleanest source for an accurate retroactive ADR.

## Step 5: Generate ADRs

For each identified decision, create a file at `docs/ADRs/0NN-<kebab-title>.md` (use the next sequential number after the highest existing ADR; **never reuse a number**).

Match the existing ADR template exactly:

```markdown
# ADR-NNN: [Decision Title]

**Status:** Accepted

**Date:** YYYY-MM-DD (commit date if known, otherwise "Retroactive")

**Evidence:** [file paths with line/symbol references]; [commit hashes]; [bench output if perf-related]; [dev spec path if applicable]

## Context

[What problem or need prompted this decision? 2-3 sentences. Reference the prior state if this supersedes a previous decision.]

## Decision

[What was decided? Be specific — name the modules, patterns, or APIs chosen. Use code blocks for signatures or shapes when needed.]

## Alternatives Considered

[ONLY include alternatives with evidence from PR threads, commit messages,
code comments, or dev specs. If no alternatives were documented, write:
"No alternatives documented in available evidence. Add if known."
NEVER fabricate alternatives that sound plausible but have no source.]

## Rationale

[WHY was this decision made? Numbered list — each point grounded in a piece of evidence cited above.]

## Consequences

- **Positive:** [Benefits gained — measurable where possible (e.g. "render dropped from 12 µs to 6.4 µs")]
- **Negative:** [Tradeoffs accepted]
- **Risks:** [What could go wrong; how the bench / health check would surface it]

## References

- Commit: [hash]
- PR: [link if applicable]
- Dev spec: `docs/dev-specs/<file>.md` (if applicable)
- Related ADRs: [supersedes / superseded by / depends on]
```

### Rules

- **One decision per ADR** — don't combine unrelated decisions, even if they shipped in the same PR.
- **WHY over WHAT** — the codebase shows WHAT; the ADR must explain WHY.
- **Min 2 evidence signals** — a single commit message alone is not enough. A decision needs at least 2 of: commit, dev spec, code-pattern signal, code comment, bench output, PR thread. If you only have one signal, downgrade to "candidate" and ask the user for the second.
- **Never fabricate alternatives** — if the evidence doesn't show alternatives were considered, say "No alternatives documented" instead of inventing plausible ones. The ADR should prompt the user to fill in what they remember.
- **Cite line / symbol level** — Evidence should be `lua/beast/libs/statusline/init.lua` (`state.cache`, `eval_component`), not just the file path. Match the precision used in ADR-013.
- **Never delete ADRs** — ADRs are immutable history. If a decision is replaced, create a new ADR and mark the old one `Status: Superseded by ADR-NNN` (see ADR-010 → ADR-013 for the canonical example). If a decision no longer applies (feature removed), change status to `Status: Deprecated — [reason]`. The original content stays.
- **Numbering is monotonic** — even when an ADR is superseded, the supersession is a *new* ADR with a *new* number.

## Step 6: Update INDEX.md

Append the new ADR rows to `docs/ADRs/INDEX.md`. Match the existing column shape exactly:

```markdown
| [0NN](0NN-kebab-title.md) | Title | Accepted | YYYY-MM-DD |
```

If a new ADR supersedes an existing one, also update the existing row's `Status` column to `Superseded by [0NN](0NN-kebab-title.md)`.

## Step 7: Present for Review

Show the list of generated ADRs as a single message with one-line summaries. Ask the user:

- "Are these accurate?"
- "Any to merge / split?"
- "Any decisions I missed?"
- "Any 'No alternatives documented' lines you can fill in from memory?"

The user fills in lived knowledge that no source captured. That's the whole point of the human review step — never paper over it by inventing plausible alternatives.

## Two Modes

### Retroactive Mode (default)

Sweep git history + dev specs and generate ADRs for past decisions. Use for:

- First-time setup (catching up on undocumented decisions)
- After a major reshape lands without a dev spec
- Periodic backfill to keep `docs/ADRs/` aligned with `lua/beast/libs/`

### Going-Forward Mode

When invoked from `/tec-implement` after a dev spec lands, generate **a single ADR** for the architectural decision being committed *now*. The dev spec is the primary input; the ADR's Evidence line cites the dev spec path plus the implementing commit hash. This is the path that produces the highest-fidelity ADRs because the rationale is fresh.

## Tips

- A dev spec that landed but has no matching ADR is your **first** target — the rationale is already written.
- Migration / replacement commits (e.g. ADR-009's heirline → native) almost always deserve an ADR.
- If a function has a `-- WHY:` comment, follow the comment up to the introducing commit — that comment exists *because* the author knew the decision needed documenting.
- Performance ADRs need numbers in Evidence. A decision that "made statusline faster" with no `BENCH …` line is not an ADR, it's a vibe.
- ADRs that change shape (caching, async boundaries, namespace lifecycle) tend to come back as bugs — an explicit ADR with Risks documented makes the bug easier to triage.
