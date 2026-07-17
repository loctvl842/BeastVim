# Dev Spec: Hunk Stage / Reset / Unstage for `beast.libs.git`

## Problem

`beast.libs.git` currently provides view-only Git integration: it computes hunks against `HEAD`, places signs, and supports navigation + preview. It cannot **stage**, **reset**, or **unstage** hunks — the three actions users expect from a gutter-diff plugin. This forces them back to `:G add -p` / external tools whenever they want to commit by hunk.

Adding these actions also requires **changing the diff reference from `HEAD` to the index** (`git show :file`). Without that change, staging a hunk would not remove its gutter mark — the buffer would still differ from HEAD even after staging. (This was already flagged in the mini.diff comparison as "borrow #2".)

Once we diff against the index, we get a second diff opportunity: index vs HEAD. That's what enables **staged signs** — a visual indication that "this line is staged but not committed". Gitsigns calls these `GitSignsStagedAdd/Change/Delete`; we want the equivalent.

## Goals

1. `Git.stage_hunk()`, `Git.unstage_hunk()`, `Git.reset_hunk()` — operate on the hunk under cursor (or a visual range).
2. Switch reference text from `HEAD:file` to `:file` (index).
3. Compute a second diff (`HEAD` vs index) → render **staged** signs in a distinct visual tier.
4. Extend statuscolumn routing groups to handle `BeastGitStaged{Add,Change,Delete,TopDelete,Changedelete}`.
5. Existing `next_hunk`/`prev_hunk`/`preview_hunk` continue to work and (optionally) gain a `target = "unstaged"|"staged"|"all"` opt.

## Non-goals

- No partial-line hunks (i.e. word-level stage). Both gitsigns and mini.diff stage at line granularity; matching that is enough.
- No `reset_buffer` / `stage_buffer` in v1 — easy follow-ups once hunk-level works.
- No undo-stage stack (gitsigns has a deprecated `undo_stage_hunk`; new pattern is "call `stage_hunk` on a staged sign to unstage that hunk" — we'll adopt that).
- No worker-thread diff. Index diffs are computed on the main loop, same as the current HEAD diff.

---

## Comparison: how the reference designs do it

### Gitsigns (`/Users/loctvl842/.local/share/nvim/lazy/gitsigns.nvim`)

**Apply mechanism (`lua/gitsigns/git.lua:201`):**

```lua
function Obj:stage_hunks(hunks, invert)
  self:ensure_file_in_index()                        -- handle new files
  local patch = hunks_mod.create_patch(relpath, hunks, mode_bits, invert)
  self.repo:command({
    'apply', '--whitespace=nowarn', '--cached', '--unidiff-zero', '-',
  }, { stdin = patch })
end
```

Patch format is a synthetic unified-zero-context diff written to `git apply --cached`'s stdin. The `invert` flag is the unstage path — same patch, reversed direction.

**Stage / unstage / reset** all live in `lua/gitsigns/actions.lua`:
- `stage_hunk`: tries the unstaged hunk first; if not found, tries the staged one with `invert=true`. **Same key, both directions.**
- `reset_hunk`: pure buffer mutation — `util.set_lines(bufnr, lstart, lend, hunk.removed.lines)`. No git invocation.
- All wrapped in `mk_repeatable(async.create(...))` for dot-repeat + async.

**Two-diff model (`lua/gitsigns/cache.lua:30`):**

```lua
--- @field hunks?              Gitsigns.Hunk.Hunk[]   -- index vs buffer (unstaged)
--- @field hunks_staged?       Gitsigns.Hunk.Hunk[]   -- HEAD vs index (staged)
--- @field staged_diffs        Gitsigns.Hunk.Hunk[]   -- session-local stage history
```

**Highlight naming (`lua/gitsigns/highlight.lua:31`):**

```lua
local hl = ('GitSigns%s%s%s'):format(staged and 'Staged' or '', cty, kind)
-- → GitSignsAdd, GitSignsStagedAdd, GitSignsChangeNr, GitSignsStagedChangeNr, ...
```

Staged groups fall back to their unstaged counterpart if user hasn't themed them. Smart, lets minimal themes still work.

---

### mini.diff (`/Users/loctvl842/Documents/GitDepot/mini.diff/lua/mini/diff.lua`)

**Apply mechanism (`H.git_format_patch:1811`):**

```lua
local res = {
  string.format('diff --git a/%s b/%s', rel_path, rel_path),
  'index 000000..000000 ' .. mode_bits,
  '--- a/' .. rel_path,
  '+++ b/' .. rel_path,
}
for _, h in ipairs(hunks) do
  table.insert(res, string.format('@@ -%d,%d +%d,%d @@',
    start, h.ref_count, start + offset, h.buf_count))
  for i = h.ref_start, h.ref_start + h.ref_count - 1 do
    table.insert(res, '-' .. ref_lines[i] .. cr_eol)
  end
  for i = h.buf_start, h.buf_start + h.buf_count - 1 do
    table.insert(res, '+' .. buf_lines[i] .. cr_eol)
  end
  offset = offset + (h.buf_count - h.ref_count)
end
```

Then:

```lua
H.git_apply_patch = function(path_data, patch)
  vim.loop.spawn('git', {
    args = { 'apply', '--whitespace=nowarn', '--cached', '--unidiff-zero', '-' },
    cwd = path_data.cwd, stdio = { stdin, nil, nil },
  }, ...)
  -- stream patch to stdin
end
```

**No unstage.** README is explicit: "Applying hunks means staging, a.k.a adding to index. There is no capability for unstaging hunks. Use full Git client for that."

**No staged signs either** — the diff is always buf-vs-index, so once you stage a hunk it disappears from the gutter. Cleaner but less informative than gitsigns' two-tier view.

**Source abstraction:** `do_hunks(buf_id, action, opts)` dispatches `action ∈ {"apply", "reset", "yank"}`, where the active source provides `apply_hunks`. This separates "what's a hunk" from "what does staging mean for this ref type" — the `save` source has no `apply_hunks` and silently no-ops.

---

### Side-by-side

| Concern | Gitsigns | mini.diff | Recommendation for beast |
|---|---|---|---|
| Stage patch construction | Module `gitsigns.hunks.create_patch` | Inline in `H.git_format_patch` | New `lua/beast/libs/git/patch.lua` — keep diff/patch separated from io |
| Stage IPC | `repo:command{...}` (sync wrapped in async) | `vim.loop.spawn` direct | `vim.system(..., callback)` (modern, matches the rest of the lib) |
| Unstage | Same key, `invert=true` | Not supported | Match gitsigns — same `stage_hunk()` toggles |
| Reset | `util.set_lines` (pure buffer) | `util.set_lines` (pure buffer) | Identical approach |
| Two-tier signs | Yes (`GitSignsStaged*`) | No | **Yes** — clearly worth it |
| Ref text | Index (`:file`) | Index (`:file`) | Switch beast from HEAD to index |
| New-file handling | `git add --intent-to-add` | Falls back to "no relpath" no-op | Match gitsigns — `--intent-to-add` so first stage works |
| CRLF handling | Reads `i_crlf` / `w_crlf` from `ls-files --eol` | Reads `eolinfo:index` from `ls-files --format` | Match either; mini.diff's `--format=` is cleaner |
| Repeatability | `mk_repeatable(async.create(...))` | Not repeatable | Worth adding — dot-repeat is expected UX |

---

## Design

### File layout (new + modified)

```
lua/beast/libs/git/
  init.lua          (modified — new public actions, two-tier state)
  config.lua        (modified — new highlight name keys, optional disable flag)
  repo.lua          (modified — get_base now reads index, +get_path_data)
  diff.lua          (unchanged)
  hunks.lua         (unchanged for unstaged; new expand_staged_signs)
  signs.lua         (modified — split namespace into "unstaged" and "staged",
                     route via BeastGit* + BeastGitStaged*)
  patch.lua         (NEW — pure: hunks → unified-zero patch lines)
  apply.lua         (NEW — async: write patch to `git apply --cached` stdin)
  actions.lua       (NEW — stage_hunk / unstage_hunk / reset_hunk wired together)
  nav.lua           (modified — optional target filter)
  preview.lua       (unchanged for v1)
  highlights.lua    (modified — add BeastGitStaged* link tags)
  health.lua        (modified — check new namespaces / hl groups)
```

### State shape (per buffer)

```lua
---@class Beast.Git.BufState
---@field ctx Beast.Git.RepoCtx
---@field path_data Beast.Git.PathData?     -- NEW: cached for apply/format-patch
---@field base string                        -- Index text (was: HEAD text)
---@field head string?                       -- NEW: HEAD text (for staged diff)
---@field hunks Beast.Git.RawHunk[]          -- Unstaged (base vs current)
---@field staged_hunks Beast.Git.RawHunk[]   -- NEW: Staged (head vs base)
---@field line_signs table<integer, { type, staged: boolean }>  -- merged
---@field timer uv.uv_timer_t?
---@field running boolean
---@field dirty boolean
---@field last_diff_ms number?
```

`path_data` mirrors mini.diff's struct and is needed for every apply call. Cached at attach, refreshed on `BufFilePost` (already detach+reattach today).

### Reference text fetch

`repo.get_base` changes from:

```lua
vim.system({ "git", "-C", ctx.toplevel, "show", "HEAD:" .. ctx.relpath }, ...)
```

to:

```lua
-- Index version (default ref). Empty string for untracked/intent-to-add.
vim.system({ "git", "-C", ctx.toplevel, "show", ":" .. ctx.relpath }, ...)
```

Add a sibling `repo.get_head(ctx, cb)` for the HEAD version (used for staged diff). Both can fail silently → empty string, same as today.

`repo.get_path_data(ctx, cb)` — new, runs `git ls-files -z --full-name --format='%(objectmode) %(eolinfo:index) %(path)'`. Returns `{ mode_bits, eol, rel_path }`. Borrowed verbatim from mini.diff:1791.

### Diff pipeline (one buffer, one re-diff)

```
recompute(buf, st):
  current = read_buffer()                          -- string
  st.hunks        = diff.compute(st.base, current) -- unstaged
  st.staged_hunks = diff.compute(st.head, st.base) -- staged   ← NEW
  unstaged_signs  = hunks.expand_signs(st.hunks, n)
  staged_signs    = hunks.expand_signs(st.staged_hunks, n)
  st.line_signs   = merge(unstaged_signs, staged_signs)  -- unstaged wins
  signs.place(buf, st.line_signs)
```

Merge rule: if both diffs touch the same line, the unstaged sign wins (because the staged change is "older history" relative to the user's current edits). This matches gitsigns.

`schedule_diff(buf, refresh_base)` becomes `schedule_diff(buf, refresh_base, refresh_head)`. Triggers:

| Event | refresh_base (index) | refresh_head |
|---|---|---|
| Initial attach | yes | yes |
| `on_lines` | no | no |
| `BufWritePost` | yes | no |
| `FocusGained` | yes | yes |
| **After stage/unstage** | yes | no |
| (future) `.git/HEAD` fs_event | no | yes |

### Sign placement: two namespaces

Today: one namespace `beast_git_signs`, extmark per changed line with `sign_hl_group = "BeastGit<Type>"`.

After: two namespaces:
- `beast_git_signs_unstaged` — `BeastGit{Add,Change,Delete,TopDelete,Changedelete}` (unchanged routing tags)
- `beast_git_signs_staged` — `BeastGitStaged{Add,Change,Delete,TopDelete,Changedelete}` (new)

Two namespaces (instead of one with mixed tags) so:
1. We can clear/replace each independently.
2. Statuscolumn classifier just adds new entries to its `HL_BY_TYPE` map — no special casing.

Priority: staged signs get a lower priority (5) than unstaged (6), so the merge rule above is enforced even at the extmark layer.

`signs.lua` API:

```lua
signs.place_unstaged(buf, line_signs)   -- replaces clear+place split
signs.place_staged(buf, line_signs)
signs.clear(buf)                         -- still clears both namespaces
signs.namespaces = { unstaged = NS_U, staged = NS_S }  -- for statuscolumn consumer
```

### Statuscolumn integration

`lua/beast/libs/statuscolumn/signs.lua` already has:

```lua
HL_MAP = {
  BeastGitAdd         = { hl = "BeastStcGitAdd",    icon_key = "add" },
  BeastGitChange      = { hl = "BeastStcGitChange", icon_key = "change" },
  ...
}
```

Add five entries:

```lua
BeastGitStagedAdd         = { hl = "BeastStcGitStagedAdd",    icon_key = "staged_add" },
BeastGitStagedChange      = { hl = "BeastStcGitStagedChange", icon_key = "staged_change" },
BeastGitStagedDelete      = { hl = "BeastStcGitStagedDelete", icon_key = "staged_delete" },
BeastGitStagedTopDelete   = { hl = "BeastStcGitStagedDelete", icon_key = "staged_topdelete" },
BeastGitStagedChangedelete= { hl = "BeastStcGitStagedChange", icon_key = "staged_changedelete" },
```

Add five highlight groups in `statuscolumn/highlights.lua` (using current palette pattern):

```lua
GitAdd          = { fg = p.accent3 },
GitChange       = { fg = p.accent2 },
GitDelete       = { fg = p.accent1 },
-- NEW: dimmed/desaturated variants for staged
GitStagedAdd    = { fg = blend(p.accent3, 0.5, p.background) },
GitStagedChange = { fg = blend(p.accent2, 0.5, p.background) },
GitStagedDelete = { fg = blend(p.accent1, 0.5, p.background) },
```

Visual rule: **staged signs are a desaturated version of the unstaged color** — same hue family signals "this is a git change", lower intensity signals "already accepted into index". This is the gitsigns default mental model. User can override either tier independently.

Icons can default to the same glyphs for both tiers (`add = "│"` etc.) — color carries the distinction. Allow per-tier override in `config.icons`:

```lua
icons = {
  add = "│",       -- applies to both tiers unless overridden
  staged_add = "┊", -- optional: explicit staged glyph
  ...
}
```

Fall back to base icon if `staged_*` not configured.

### Public API

```lua
-- Existing
Git.get_hunks(buf?)                                     -- unstaged hunks (unchanged)
Git.get_staged_hunks(buf?)                              -- NEW: staged hunks
Git.next_hunk(opts?) / prev_hunk(opts?)                 -- gains opts.target
Git.preview_hunk() / preview_hunk_range(s, e)           -- unchanged in v1

-- New
Git.stage_hunk(opts?)                                   -- toggle: stage unstaged, unstage staged
Git.unstage_hunk(opts?)                                 -- explicit unstage
Git.reset_hunk(opts?)                                   -- restore line(s) from base
-- opts: { range = {start, end}? }   -- omit → hunk under cursor
```

**Toggle semantics on `stage_hunk`** (gitsigns pattern, lines 244-251):
1. Look for an unstaged hunk at cursor/range → if found, stage it (`invert=false`).
2. Otherwise look for a staged hunk → if found, unstage it (`invert=true`).
3. Otherwise: notify "No hunk".

This is the most ergonomic UX: one keymap (`<leader>hs`) does the right thing whether you're on a green or grey sign.

### Patch construction (`patch.lua`)

Pure function, no IO:

```lua
---@param relpath string
---@param mode_bits string  -- e.g. "100644"
---@param hunks Beast.Git.RawHunk[]
---@param base_lines string[]    -- index text split by \n
---@param current_lines string[] -- buffer lines
---@param invert? boolean        -- true → unstage (swap +/-)
---@param cr_eol? boolean        -- append \r before \n for CRLF files
---@return string[]              -- patch lines (no trailing \n; caller joins)
function M.create(relpath, mode_bits, hunks, base_lines, current_lines, invert, cr_eol)
  ...
end
```

Body follows mini.diff:1815 — header + per-hunk `@@ -a,b +c,d @@` + `-base`/`+current` lines, with running `offset` for cumulative drift when staging multiple hunks. `invert=true` swaps `a_*`/`b_*` in the hunk header and `-`/`+` in body lines.

### Apply (`apply.lua`)

```lua
---@param ctx Beast.Git.RepoCtx
---@param patch_lines string[]
---@param cb fun(err?: string)
function M.apply_cached(ctx, patch_lines, cb)
  local patch = table.concat(patch_lines, "\n") .. "\n"
  vim.system(
    { "git", "-C", ctx.toplevel, "apply", "--whitespace=nowarn", "--cached", "--unidiff-zero", "-" },
    { stdin = patch, text = true },
    vim.schedule_wrap(function(result)
      if result.code ~= 0 then
        return cb(result.stderr or "git apply failed")
      end
      cb(nil)
    end)
  )
end
```

`vim.system` (not `vim.loop.spawn`) — cleaner, matches the rest of the lib, gives us `stdin` directly.

For **new files** (no `relpath` resolvable in index), `actions.lua` runs `git add --intent-to-add <relpath>` first, then re-fetches `path_data`, then applies.

### Actions (`actions.lua`)

```lua
local repo = require("beast.libs.git.repo")
local patch_mod = require("beast.libs.git.patch")
local apply = require("beast.libs.git.apply")

local function hunk_at_cursor(hunks)
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  for _, h in ipairs(hunks) do
    local from = h.b_start == 0 and 1 or h.b_start
    local to = from + math.max(h.b_count, 1) - 1
    if lnum >= from and lnum <= to then return h end
  end
end

function M.stage_hunk(opts)
  local Git = require("beast.libs.git")
  local buf = vim.api.nvim_get_current_buf()
  local st  = Git._get_state(buf)
  if not st then return end

  -- Toggle: prefer unstaged, fall back to staged-with-invert.
  local target = hunk_at_cursor(st.hunks)
  local invert = false
  if not target then
    target = hunk_at_cursor(st.staged_hunks)
    invert = true
    if not target then
      vim.notify("No hunk to stage/unstage", vim.log.levels.INFO)
      return
    end
  end

  local base_lines    = vim.split(st.base, "\n", { plain = true })
  local current_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local patch_lines = patch_mod.create(
    st.path_data.rel_path, st.path_data.mode_bits,
    { target }, base_lines, current_lines, invert, st.path_data.eol == "crlf"
  )

  apply.apply_cached(st.ctx, patch_lines, function(err)
    if err then
      return vim.notify("git apply: " .. err, vim.log.levels.ERROR)
    end
    -- Force base refresh; head unchanged.
    Git._schedule_diff(buf, true, false)
  end)
end

function M.unstage_hunk(opts)
  -- Same as stage_hunk but inverted, looking only in staged_hunks.
  -- ...
end

function M.reset_hunk(opts)
  local Git = require("beast.libs.git")
  local buf = vim.api.nvim_get_current_buf()
  local st  = Git._get_state(buf)
  if not st then return end

  local h = hunk_at_cursor(st.hunks)
  if not h then return vim.notify("No hunk to reset", vim.log.levels.INFO) end

  local base_lines = vim.split(st.base, "\n", { plain = true })
  local lstart, lend
  if h.type == "add" then
    lstart, lend = h.b_start - 1, h.b_start - 1 + h.b_count
    vim.api.nvim_buf_set_lines(buf, lstart, lend, false, {})
  elseif h.type == "delete" then
    lstart = h.b_start  -- 0 → insert above line 1
    local ref_lines = {}
    for i = h.a_start, h.a_start + h.a_count - 1 do
      ref_lines[#ref_lines + 1] = base_lines[i]
    end
    vim.api.nvim_buf_set_lines(buf, lstart, lstart, false, ref_lines)
  else  -- change
    lstart, lend = h.b_start - 1, h.b_start - 1 + h.b_count
    local ref_lines = {}
    for i = h.a_start, h.a_start + h.a_count - 1 do
      ref_lines[#ref_lines + 1] = base_lines[i]
    end
    vim.api.nvim_buf_set_lines(buf, lstart, lend, false, ref_lines)
  end
  -- on_lines triggers the re-diff automatically.
end
```

Reset is pure buffer mutation → no git call → no race with apply.

### Init.lua wiring

Add `_schedule_diff` to the `M` table (already exists internally — just expose as `M._schedule_diff = schedule_diff`).

Add expose:

```lua
function M.stage_hunk(opts)   require("beast.libs.git.actions").stage_hunk(opts)   end
function M.unstage_hunk(opts) require("beast.libs.git.actions").unstage_hunk(opts) end
function M.reset_hunk(opts)   require("beast.libs.git.actions").reset_hunk(opts)   end
function M.get_staged_hunks(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local st = state[buf]
  return st and st.staged_hunks or {}
end
```

---

## Phases  *(all complete — see ## Completed below)*

### Phase 1: Switch ref from HEAD to index (foundation)
1. Modify `repo.get_base` to use `:file` instead of `HEAD:file`.
2. Add `repo.get_head` for HEAD text.
3. Add `repo.get_path_data`.
4. Extend `BufState` with `head`, `staged_hunks`, `path_data`.
5. `recompute` computes both diffs, merges signs (priority-based).
6. `schedule_diff` accepts `refresh_base, refresh_head`.
7. Add `Git.get_staged_hunks(buf?)`.
8. **Verify:** existing gutter shows unstaged, no regression in nav/preview, 5k bench still passes.

### Phase 2: Two-tier sign rendering
1. Split `signs.lua` namespace into unstaged/staged.
2. Extend `statuscolumn/signs.lua` `HL_MAP` with `BeastGitStaged*` entries.
3. Add `BeastStcGitStaged{Add,Change,Delete}` highlight groups (palette-derived blends).
4. Update `statuscolumn/config.lua` icons table to optionally accept `staged_*` keys.
5. **Verify:** stage a hunk via CLI (`git add -p`), see grey sign appear in gutter; edit on top of staged region, see green sign override.

### Phase 3: Stage / unstage / reset
1. Write `patch.lua` (pure function, unit-testable via in-process bench script).
2. Write `apply.lua`.
3. Write `actions.lua` (stage_hunk toggle, explicit unstage, reset).
4. Expose `Git.stage_hunk` / `Git.unstage_hunk` / `Git.reset_hunk`.
5. Handle new-file path: detect missing `path_data`, run `git add --intent-to-add`, retry.
6. **Verify:**
   - Stage hunk on cursor → patch applies → gutter mark turns grey → `git diff --cached` shows the hunk.
   - Press stage again on same hunk → unstages → mark turns green again.
   - Edit, then reset_hunk → buffer reverts to index version, gutter clears.
   - Multi-hunk file: stage two non-adjacent hunks one at a time → both staged correctly (offset math).

### Phase 4: Polish + dot-repeat
1. Wrap `stage_hunk`/`reset_hunk` with a minimal repeatability shim (no async lib needed — just save last action in a module-local var, expose `Git.repeat_action()`).
2. Add `target = "unstaged" | "staged" | "all"` to `next_hunk`/`prev_hunk`.
3. Update `health.lua` to check new namespaces + highlight groups.
4. Update `docs/CODEMAP/` if it covers `libs/git`.

---

## Test plan

| Test | How |
|---|---|
| Stage clean file (no changes) | Notify "No hunk", exit 0 |
| Stage single-line edit | `git diff --cached` shows it, gutter turns grey |
| Stage → restage (toggle) | Second call unstages; `git diff --cached` empty |
| Stage hunk N of M, then hunk 1 of M | Both staged correctly (offset accumulation) |
| Reset add | Lines deleted from buffer, gutter clears |
| Reset delete | Lines reinserted from index, gutter clears |
| Reset change | Lines replaced with index version |
| New file (untracked) | `git add --intent-to-add` then stage works |
| CRLF file | Patch has `\r\n` endings, git apply succeeds |
| External `git add` | `FocusGained` re-fetches HEAD → staged signs appear |
| `bench-git-wezterm.sh` | Phase 1 may add ~1 ms (second diff per cycle). Acceptable if median <8 ms at 1 ms debounce. |

## Risks

1. **Offset math when staging multiple hunks** — easy to get wrong. mini.diff's loop pattern (lines 1822-1837) is the reference. Unit-test via `patch.lua` with a synthetic 3-hunk fixture, compare output byte-for-byte against `git diff` of the same change.
2. **CRLF detection failure** — silent corruption if eol detection is wrong. Borrow mini.diff's `--format=%(eolinfo:index)` exactly; do not invent.
3. **Race between stage apply and re-diff** — fix by calling `schedule_diff(buf, true, false)` only after apply's callback fires. Single-flight bit handles concurrent edits during the apply.
4. **Index-as-ref breaks first-commit case** — `git show :file` fails for untracked files; current code already handles `result.code ~= 0 → cb("")`. Same fallback works.
5. **Staged signs feel noisy** — mitigated by desaturation: visible but unobtrusive. User can override icons to blank string to hide entirely.

## Open questions for you

1. **Toggle vs explicit?** Should `stage_hunk` toggle (gitsigns) or always stage (mini.diff)? I'm recommending toggle with separate `unstage_hunk` for explicitness.
2. **Phase 2 first or Phase 3 first?** Phase 2 gives no new actions but unlocks the visual feedback that makes Phase 3 testable. I recommend Phase 2 first.
3. **Per-tier icons?** Default to "same icon, different color"? Or different icons too (`│` vs `┊`)?
4. **Health check threshold change?** Phase 1 doubles the diff work per cycle. Should bench thresholds bump from "median ≤ 70 ms / p99 ≤ 90 ms" to "median ≤ 80 ms / p99 ≤ 100 ms"?
