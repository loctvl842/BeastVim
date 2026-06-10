---
name: tec-update-codemaps
description: "Scan BeastVim and regenerate token-lean architecture documentation under docs/CODEMAPS/. Use when asked to 'update codemaps', 'generate codemap', 'map the codebase', 'project architecture', 'save project context', 'what does this project look like'."
---

# Update Codemaps — BeastVim

Generate token-lean architecture documentation that lets agents (and humans) look up project structure, navigate the require graph, and resume work quickly without re-reading the whole tree.

The output lives at `docs/CODEMAPS/`. It must stay **token-lean** (each file under ~1000 tokens) and **shape-stable** so day-to-day diffs are meaningful.

## When to Use

- Starting work on an unfamiliar area of the codebase
- After a major dev spec lands (new lib, refactor across libs, removal of a module)
- After `/tec-implement` finishes a multi-phase spec — codemaps almost always need a refresh
- When the daily health report flags codemaps as stale (> 7 days)
- Periodically (weekly) to keep docs aligned with reality

## Step 1: Scan Project Structure

BeastVim has a known shape — don't re-discover it from scratch every run. Confirm the shape, then look for changes since last generation.

### 1a — Confirm the canonical layout

```
lua/beast/
├── init.lua              ← top-level setup; wires libs + globals + ColorScheme refresh
├── option.lua            ← vim options
├── icon.lua              ← icon registry
├── util/                 ← Util.* shared helpers
│   ├── init.lua
│   └── ...
├── libs/                 ← reusable UI components, each follows AGENTS.md § File Structure
│   ├── view.lua          ← Beast.View base class (every buf+win pair subclasses this)
│   ├── animate.lua       ← shared animation engine (pure math)
│   └── <lib>/init.lua    ← per-lib public API
└── plugins/              ← plugin specs (loaded via beast.libs.packer)
    ├── init.lua
    └── ...
```

Read `lua/beast/init.lua` to see which libs are wired in (the canonical list of "live" libs).

### 1b — Detect what changed since last generation

```bash
last=$(grep -oE 'Generated: [0-9]{4}-[0-9]{2}-[0-9]{2}' docs/CODEMAPS/INDEX.md | head -1 | awk '{print $2}')
git log --since="$last" --name-only --pretty=format: -- lua/ | sort -u
```

The list of changed files is your scan target. Files not in the list don't need re-reading.

### 1c — Detect new libs / removed libs

```bash
ls lua/beast/libs/ | sort
```

Compare against the libs listed in the previous `INDEX.md`'s *Project Stats*. Any new directory under `lua/beast/libs/` that isn't a single `.lua` file is a candidate new lib (look for `init.lua`).

### 1d — Discover supplementary documentation

Skim `docs/dev-specs/*.md` and `docs/ADRs/*.md` for **architecture rationale** the code alone doesn't reveal:

- Why a lib is shaped a certain way (ADR-002, ADR-012, etc.)
- Why a shared module exists (ADR-004, ADR-005)
- Why something *isn't* a feature (ADR-010 → ADR-013 supersession)

These don't go *into* the codemap — but they shape what the codemap chooses to highlight.

## Step 2: Generate Codemaps

Output two files under `docs/CODEMAPS/`. Match the existing shape exactly — don't introduce new sections without a reason.

### `architecture.md` — system shape

| Section | Contents |
|---------|----------|
| Entry Point | `init.lua → require("beast").setup()` |
| Module Tree | ASCII tree of `lua/beast/` with one-line descriptions per file/dir. Match the depth of the existing file. |
| Globals Registered at Setup | Table: `Util`, `Key`, `Buffer`, `Icon`, `Toast`, `Theme`, etc. → module → purpose. Source of truth: `lua/beast/init.lua`. |
| Setup Flow | Numbered list, what runs in what order during `beast.setup()`. Important for understanding why some libs require others. |
| ColorScheme Reload Contract | List of modules whose `*.highlights` are reset on `ColorScheme` autocmd (`package.loaded[...] = nil` pattern). Cross-reference ADR-008. |
| Plugin Loading Strategy | `beast.libs.packer` loading phases — which plugins load when and how. |
| Cross-cutting Conventions | One-line callouts to AGENTS.md sections (View pattern, Config pattern, Type Naming) — the **link**, not the content. The codemap stays lean by referencing AGENTS.md, not duplicating it. |

### `libraries.md` — per-lib breakdown

For each lib under `lua/beast/libs/` (every directory + the top-level `view.lua`, `animate.lua`, `buf.lua`):

```markdown
## <lib-name>

**Path:** `lua/beast/libs/<lib>/`
**Type:** floating window / split panel / pure module / ...
**Subclasses View:** Yes / No (if Yes, name the View subclass)

### Public API
- `M.<fn>(args) → returns` — one-line description
- ...

### File Structure
init.lua    — public API, owns module-level state
ui.lua      — buf+win lifecycle
state.lua   — per-instance state class
config.lua  — defaults, live cfg, normalizers

### Dependencies
- Internal: beast.libs.view, beast.util.colors
- Plugin: <only if non-trivial>

### Highlights / Namespace
- Namespace: `beast.<lib>.<purpose>`
- Reset on ColorScheme: yes / no
```

Optional third file: `plugins.md` — only if `lua/beast/plugins/` has grown to more than ~5 files. Currently it has very few; the libs are the architectural surface, not the plugin specs.

### Formatting Rules

- **File paths and function signatures** over full code blocks
- **ASCII trees and arrows (`→`)** over verbose prose
- **Each codemap under ~1000 tokens** (the current `architecture.md` token estimate is ~950 — that's the upper bound)
- **No implementation details** — structure and navigation only. Implementation lives in the file, not the codemap.
- **Reference, don't duplicate** — when a fact lives in `AGENTS.md` (e.g. the *View Pattern*), link to it; don't re-explain it
- **Reference, don't duplicate ADRs** — the codemap names the ADR (e.g. "see ADR-013") rather than restating the decision

## Step 3: Diff Detection

Before overwriting:

```bash
diff -u docs/CODEMAPS/architecture.md /tmp/new-architecture.md
diff -u docs/CODEMAPS/libraries.md    /tmp/new-libraries.md
```

If the diff is **> 30 % of the file's lines**, show the diff summary and ask the user before overwriting. Big jumps usually mean either: a major refactor just landed (legitimate), or the regeneration scanned the wrong tree (illegitimate). The 30 % gate catches both.

If the diff is **≤ 30 %**, update in place — that's the steady-state case.

## Step 4: Add Metadata Header

Every codemap file starts with:

```markdown
<!-- Generated: YYYY-MM-DD | Files scanned: N | Token estimate: ~NNN -->
```

The token estimate is a count, not a guess — use `wc -w` on the file as a rough proxy (1.3× word count ≈ token count for English; for code-heavy markdown use `wc -c / 4`).

The `Generated` date is what `/tec-health` reads to flag staleness — keep the format exact.

## Step 5: Generate `INDEX.md`

`docs/CODEMAPS/INDEX.md` is the entry point. It stays small.

```markdown
<!-- Generated: YYYY-MM-DD | Files scanned: N | Token estimate: ~NNN -->

# BeastVim Codemaps

Quick-reference architecture documentation. Regenerate with `/tec-update-codemaps`.

## Files
- [architecture.md](architecture.md) — system overview, module boundaries, setup flow
- [libraries.md](libraries.md) — per-library structure, public APIs, dependencies
- [plugins.md](plugins.md) — plugin specs (only if non-trivial)

## Project Stats
- Language: Lua
- Platform: Neovim plugin (config-as-plugin)
- Lines of code: ~XX,XXX (count with `find lua -name '*.lua' | xargs wc -l | tail -1`)
- Libraries: N (list them: explorer, notify, toast, key, confirm, packer, buf, statusline, ...)
- Shared modules: view.lua, animate.lua, util/
- Last updated: YYYY-MM-DD
```

The Project Stats block is what makes `/tec-onboard` (or a fresh agent) instantly understand the scope. Keep the lib list **complete**.

## Step 6: Staleness Report

After regeneration, print a brief summary to the user:

```
Codemaps updated:
- architecture.md: <N> lines changed (<add>/<del>)
- libraries.md: <N> lines changed (<add>/<del>)

New since last generation:
- Libs added: <list or "none">
- Libs removed: <list or "none">
- New shared modules: <list or "none">
- New ADR-worthy patterns detected: <list or "none — see AGENTS.md DRY Opportunities">

Next step: review the diff, commit alongside the dev spec that prompted the regeneration.
```

The "ADR-worthy patterns" line is the cue to follow up with `/tec-adr` — codemap regeneration often surfaces shapes that landed without an ADR.

## Tips

- The codemap is a **navigation map**, not documentation. If you need to read a paragraph, the codemap is too long.
- Match the existing shape; don't restructure unless explicitly asked. A stable shape makes diffs across regenerations meaningful.
- Cross-reference AGENTS.md and ADRs heavily — that's how the codemap stays under 1000 tokens.
- If a single lib's section in `libraries.md` is growing past ~150 lines, consider splitting that lib into its own codemap file. Don't preemptively split.
- Token estimate isn't decoration — it's the gate. If a file passes ~1500 tokens, you've drifted toward documentation. Compress.
