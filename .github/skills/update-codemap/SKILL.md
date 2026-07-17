---
name: update-codemap
description: "Scan BeastVim and regenerate token-lean architecture documentation under docs/CODEMAP/. Use when asked to 'update codemap', 'generate codemap', 'map the codebase', 'project architecture', 'save project context', 'what does this project look like'."
---

# Update Codemap — BeastVim

Generate token-lean architecture documentation that lets agents (and humans) look up project structure, navigate the require graph, and resume work quickly without re-reading the whole tree.

The output lives at `docs/CODEMAP/`. It must stay **token-lean** (each file under ~1000 tokens) and **shape-stable** so day-to-day diffs are meaningful.

## When to Use

- Starting work on an unfamiliar area of the codebase
- After a major dev spec lands (new lib, refactor across libs, removal of a module)
- After `/implement-spec` finishes a multi-phase spec — codemaps almost always need a refresh
- Periodically (weekly) to keep docs aligned with reality

## Step 1: Scan Project Structure

BeastVim has a known shape — don't re-discover it from scratch every run. Confirm the shape, then look for changes since last generation.

### 1a — Confirm the canonical layout

```
lua/beast/
├── init.lua              ← top-level setup; wires libs + globals + ColorScheme refresh
├── util/                 ← Util.* shared helpers
│   ├── init.lua
│   └── ...
├── libs/                 ← reusable UI components, each follows File Structure convention
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
last=$(grep -oE 'Generated: [0-9]{4}-[0-9]{2}-[0-9]{2}' docs/CODEMAP/INDEX.md | head -1 | awk '{print $2}')
git log --since="$last" --name-only --pretty=format: -- lua/ | sort -u
```

The list of changed files is your scan target. Files not in the list don't need re-reading.

### 1c — Detect new libs / removed libs

```bash
ls lua/beast/libs/ | sort
```

Compare against the libs listed in the previous `INDEX.md`'s *Project Stats*. Any new directory under `lua/beast/libs/` that isn't a single `.lua` file is a candidate new lib (look for `init.lua`).

## Step 2: Generate Codemaps

Output two files under `docs/CODEMAP/`. Match the existing shape exactly — don't introduce new sections without a reason.

### `architecture.md` — system shape

| Section | Contents |
|---------|----------|
| Entry Point | `init.lua → require("beast").setup()` |
| Module Tree | ASCII tree of `lua/beast/` with one-line descriptions per file/dir. Match the depth of the existing file. |
| Globals Registered at Setup | Table: `Util`, `Key`, `Buffer`, `Icon`, `Toast`, `Theme`, etc. → module → purpose. Source of truth: `lua/beast/init.lua`. |
| Setup Flow | Numbered list, what runs in what order during `beast.setup()`. Important for understanding why some libs require others. |
| ColorScheme Reload Contract | List of modules whose `*.highlights` are reset on `ColorScheme` autocmd (`package.loaded[...] = nil` pattern). |
| Plugin Loading Strategy | `beast.libs.packer` loading phases — which plugins load when and how. |

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

Optional third file: `plugins.md` — only if `lua/beast/plugins/` has grown to more than ~5 files.

### Formatting Rules

- **File paths and function signatures** over full code blocks
- **ASCII trees and arrows (`→`)** over verbose prose
- **Each codemap under ~1000 tokens**
- **No implementation details** — structure and navigation only

## Step 3: Diff Detection

Before overwriting:

```bash
diff -u docs/CODEMAP/architecture.md /tmp/new-architecture.md
diff -u docs/CODEMAP/libraries.md    /tmp/new-libraries.md
```

If the diff is **> 30% of the file's lines**, show the diff summary and ask the user before overwriting.

If the diff is **≤ 30%**, update in place.

## Step 4: Add Metadata Header

Every codemap file starts with:

```markdown
<!-- Generated: YYYY-MM-DD | Files scanned: N | Token estimate: ~NNN -->
```

Use `wc -c / 4` on the file as a rough token estimate.

## Step 5: Generate `INDEX.md`

`docs/CODEMAP/INDEX.md` is the entry point. It stays small.

> **Note:** The template below is indented for readability inside this code fence. When generating the actual file, write all content at the root level — no leading spaces.

```markdown
    <!-- Generated: YYYY-MM-DD | Files scanned: N | Token estimate: ~NNN -->

    # BeastVim Codemaps

    Quick-reference architecture documentation. Regenerate with `/update-codemap`.

    ## Files
    - [architecture.md](architecture.md) — system overview, module boundaries, setup flow, ColorScheme pipeline
    - [libraries.md](libraries.md) — per-library structure, public APIs, dependencies

    ## Project Stats
    - Language: Lua
    - Platform: Neovim plugin (config-as-plugin)
    - Lines of code: ~XX,XXX (count with `find lua -name '*.lua' | xargs wc -l | tail -1`)
    - Libraries: N (list them: explorer, notify, toast, key, confirm, packer, buf, statusline, ...)
    - Shared modules: view.lua, animate.lua, util/
    - Last updated: YYYY-MM-DD
```

## Step 6: Staleness Report

After regeneration, print a brief summary:

```
Codemaps updated:
- architecture.md: <N> lines changed (<add>/<del>)
- libraries.md: <N> lines changed (<add>/<del>)

New since last generation:
- Libs added: <list or "none">
- Libs removed: <list or "none">
- New shared modules: <list or "none">
```

## Tips

- The codemap is a **navigation map**, not documentation. If you need to read a paragraph, the codemap is too long.
- Match the existing shape; don't restructure unless explicitly asked.
- If a single lib's section in `libraries.md` is growing past ~150 lines, consider splitting that lib into its own codemap file.
- Token estimate isn't decoration — it's the gate. If a file passes ~1500 tokens, you've drifted toward documentation. Compress.
