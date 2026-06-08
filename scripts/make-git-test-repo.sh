#!/usr/bin/env bash
# Build a throwaway *Lua project* git repo that exercises every porcelain v2
# status case the BeastVim explorer cares about — and produces real `.lua`
# files so the merge-conflict highlighter, gutter signs, and treesitter
# rendering can all be eyeballed against syntax-highlighted source.
#
# Usage:
#   scripts/make-git-test-repo.sh [DEST]
#
# DEST defaults to /tmp/beast-git-test-repo. The directory is wiped if it
# exists. After running, inspect with:
#   git -C $DEST status --porcelain=v2 --ignored -z | tr '\0' '\n'
#
# Project layout (a believable Neovim plugin):
#   init.lua                              entry point used by the README
#   README.md                             usage notes
#   .gitignore                            *.log + .DS_Store (drives `!` cases)
#   .luarc.json                           sumneko hint, marks it a real project
#   plugin/beastgit_fixture.lua           plugin file (user command)
#   lua/beastgit_fixture/init.lua         module table
#   lua/beastgit_fixture/util.lua         helpers
#   lua/beastgit_fixture/config.lua       defaults
#   lua/beastgit_fixture/files/*.lua      every non-conflict status fixture
#   lua/beastgit_fixture/conflicts/*.lua  every merge-conflict fixture
#
# Cases produced (XY column = porcelain v1 shorthand):
#
#   Single-axis (one side dirty):
#     M.  staged-modified           lua/beastgit_fixture/files/modified-staged.lua
#     .M  unstaged-modified         lua/beastgit_fixture/files/modified-unstaged.lua
#     A.  staged-added              lua/beastgit_fixture/files/added-staged.lua
#     D.  staged-deleted            lua/beastgit_fixture/files/deleted-staged.lua
#     .D  unstaged-deleted          lua/beastgit_fixture/files/deleted-unstaged.lua
#     R.  staged-renamed            lua/beastgit_fixture/files/renamed-new.lua  (from renamed-old.lua)
#     C.  staged-copied             lua/beastgit_fixture/files/copied-new.lua   (from copy-source.lua) *
#     ?   untracked                 lua/beastgit_fixture/files/untracked.lua
#     !   ignored                   lua/beastgit_fixture/files/ignored.log
#
#   Both axes (phase = "both"):
#     MM  modified staged + modified again        lua/beastgit_fixture/files/both-MM.lua
#     AM  added staged + modified in worktree     lua/beastgit_fixture/files/both-AM.lua
#     AD  added staged + deleted in worktree      lua/beastgit_fixture/files/both-AD.lua
#     MD  modified staged + deleted in worktree   lua/beastgit_fixture/files/both-MD.lua
#     RM  renamed + modified                       lua/beastgit_fixture/files/both-RM-new.lua
#
#   Conflicts (u record):
#     UU  both modified                            lua/beastgit_fixture/conflicts/UU.lua
#     AA  both added                               lua/beastgit_fixture/conflicts/AA.lua
#     DU  deleted by us, modified by them          lua/beastgit_fixture/conflicts/DU.lua
#     UD  modified by us, deleted by them          lua/beastgit_fixture/conflicts/UD.lua
#     UU  both modified, diff3 style (||| marker)  lua/beastgit_fixture/conflicts/UU-diff3.lua
#
#   Cases intentionally NOT produced:
#     DD  Pure both-delete merges cleanly; reaching DD requires rename/
#         rename conflicts that are not worth simulating.
#     AU / UA  Only arise from rename/rename or rename/modify conflicts.
#
# * Copy detection requires status.renames=copies (set below).
#
set -euo pipefail

DEST="${1:-/tmp/beast-git-test-repo}"

if [[ -e "$DEST" ]]; then
	echo "Removing existing $DEST"
	rm -rf "$DEST"
fi

mkdir -p "$DEST"
cd "$DEST"

git init --quiet --initial-branch=main
git config user.email "test@beastvim.local"
git config user.name  "BeastVim Test"
git config status.renames copies        # surfaces C. (copied) instead of A.
git config diff.renames copies
git config commit.gpgsign false

# Paths used throughout the script. Two directories so the explorer tree
# has visible structure and the relative paths in the status table stay
# readable.
PROJ="lua/beastgit_fixture"
FILES_DIR="$PROJ/files"
CONFLICTS_DIR="$PROJ/conflicts"
mkdir -p "$FILES_DIR" "$CONFLICTS_DIR" plugin

# ─────────────────────────────────────────────────────────────────────────────
# Project scaffolding (committed at baseline; never mutated)
# ─────────────────────────────────────────────────────────────────────────────

cat > .gitignore <<'EOF'
*.log
.DS_Store
EOF

cat > .luarc.json <<'EOF'
{
  "runtime.version": "LuaJIT",
  "diagnostics.globals": ["vim"],
  "workspace.library": []
}
EOF

cat > README.md <<'EOF'
# beastgit_fixture

A synthetic Neovim plugin used by `scripts/make-git-test-repo.sh` to
populate every porcelain-v2 status case the BeastVim explorer renders
and every merge-conflict shape the conflict highlighter paints.

```lua
require("beastgit_fixture").setup({ greeting = "hi" })
```
EOF

cat > init.lua <<'EOF'
-- Convenience entry point so `nvim -u init.lua` boots the fixture plugin.
require("beastgit_fixture").setup()
EOF

cat > plugin/beastgit_fixture.lua <<'EOF'
if vim.g.loaded_beastgit_fixture then
	return
end
vim.g.loaded_beastgit_fixture = 1

vim.api.nvim_create_user_command("BeastFixtureHello", function(opts)
	local mod = require("beastgit_fixture")
	print(mod.greet(opts.args ~= "" and opts.args or "world"))
end, { nargs = "?" })
EOF

cat > "$PROJ/init.lua" <<'EOF'
local config = require("beastgit_fixture.config")
local util = require("beastgit_fixture.util")

local M = {}

---@param opts table?
function M.setup(opts)
	config.apply(opts or {})
end

---@param who string
---@return string
function M.greet(who)
	return util.format(config.get("greeting"), who)
end

return M
EOF

cat > "$PROJ/util.lua" <<'EOF'
local M = {}

---@param template string
---@param subject string
---@return string
function M.format(template, subject)
	return string.format("%s, %s!", template, subject)
end

---@param tbl table
---@return integer
function M.count(tbl)
	local n = 0
	for _ in pairs(tbl) do
		n = n + 1
	end
	return n
end

return M
EOF

cat > "$PROJ/config.lua" <<'EOF'
local M = {}

local defaults = {
	greeting = "Hello",
	debug = false,
}

local state = vim.deepcopy(defaults)

function M.apply(opts)
	state = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

function M.get(key)
	return state[key]
end

return M
EOF

# ─────────────────────────────────────────────────────────────────────────────
# Helpers for synthesising tiny lua modules
# ─────────────────────────────────────────────────────────────────────────────

# Emit a small lua module to $1 whose function returns the literal $2.
# Each file embeds the tag in several distinct places (module header,
# `M.name`, `M.tag()`, `M.is_<tag>()`) so that git's similarity detector
# does NOT pair unrelated fixture files as copies — we need `status.renames=
# copies` for the real copy-source case, and the default 50% similarity
# threshold would otherwise turn every plain `A.` into `C.`.
write_module() {
	local path="$1" tag="$2"
	local ident="${tag//[^a-zA-Z0-9_]/_}"
	{
		echo "-- Module: ${tag}"
		echo "-- Fixture for BeastVim git status / conflict tests."
		echo "-- Auto-generated by scripts/make-git-test-repo.sh."
		echo ""
		echo "local M = {}"
		echo ""
		echo "M.name = \"${tag}\""
		echo "M.kind = \"fixture/${tag}\""
		echo ""
		# Tag-derived unique lines: drives the file's content past git's
		# default 50% similarity threshold so `status.renames=copies` (needed
		# for the real copy-source case) doesn't spuriously pair unrelated
		# fixtures together as copies.
		for i in 1 2 3 4 5 6 7 8 9 10; do
			echo "M.note_${ident}_${i} = \"${tag} note ${i}\""
		done
		echo ""
		echo "---@return string"
		echo "function M.tag()"
		echo "	return M.name"
		echo "end"
		echo ""
		echo "---@param x any"
		echo "---@return boolean"
		echo "function M.is_${ident}(x)"
		echo "	return x == M.tag()"
		echo "end"
		echo ""
		echo "return M"
	} > "$path"
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: baseline commit. Includes the files step-2 will mutate AND the
# pre-existing files that the conflict step needs both branches to share.
# ─────────────────────────────────────────────────────────────────────────────

write_module "$FILES_DIR/modified-staged.lua"   "modified-staged"
write_module "$FILES_DIR/modified-unstaged.lua" "modified-unstaged"
write_module "$FILES_DIR/deleted-staged.lua"    "deleted-staged"
write_module "$FILES_DIR/deleted-unstaged.lua"  "deleted-unstaged"
write_module "$FILES_DIR/renamed-old.lua"       "renamed-old"
write_module "$FILES_DIR/both-MM.lua"           "both-MM"
write_module "$FILES_DIR/both-MD.lua"           "both-MD"
write_module "$FILES_DIR/both-RM-old.lua"       "both-RM-old"

# Source for a copy. Long enough that git's copy detector accepts it.
cat > "$FILES_DIR/copy-source.lua" <<'EOF'
-- Copy source. Enough real Lua content that git's similarity detector
-- will treat a near-identical sibling as a copy rather than a fresh add.
local M = {}

---@param a number
---@param b number
---@return number
function M.add(a, b)
	return a + b
end

---@param a number
---@param b number
---@return number
function M.sub(a, b)
	return a - b
end

return M
EOF

# Conflict baseline files — must exist on both branches.
write_module "$CONFLICTS_DIR/UU.lua"        "UU baseline"
write_module "$CONFLICTS_DIR/DU.lua"        "DU baseline"
write_module "$CONFLICTS_DIR/UD.lua"        "UD baseline"
write_module "$CONFLICTS_DIR/UU-diff3.lua"  "UU-diff3 baseline"

git add .
git commit --quiet -m "baseline: scaffold beastgit_fixture project"

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: build the conflict scenarios FIRST (before any working-tree dirt).
#
# Branch `other` makes one side of every conflict, main makes the other,
# then we merge `other` into main and leave the result unresolved.
# ─────────────────────────────────────────────────────────────────────────────
git checkout --quiet -b other

# UU  both modified (file existed on baseline; both branches modify it)
write_module "$CONFLICTS_DIR/UU.lua" "UU from other"
# AA  both added (file new to both branches with different content)
write_module "$CONFLICTS_DIR/AA.lua" "AA from other"
# DU  deleted by us / modified by them — main will delete, other modifies
write_module "$CONFLICTS_DIR/DU.lua" "DU them-modified"
# UD  modified by us / deleted by them — other deletes, main modifies
git rm --quiet "$CONFLICTS_DIR/UD.lua"
# UU-diff3  both modified — same as UU but rendered with diff3 markers so
# the `|||||||` common-ancestor band shows up in the conflict highlighter.
write_module "$CONFLICTS_DIR/UU-diff3.lua" "UU-diff3 from other"

git add -A
git commit --quiet -m "other: divergent conflict content"

# Back to main and apply our side.
git checkout --quiet main

write_module "$CONFLICTS_DIR/UU.lua"       "UU modified on main"
write_module "$CONFLICTS_DIR/AA.lua"       "AA from main"
git rm --quiet                              "$CONFLICTS_DIR/DU.lua"
write_module "$CONFLICTS_DIR/UD.lua"       "UD us-modified"
write_module "$CONFLICTS_DIR/UU-diff3.lua" "UU-diff3 from main"

git add -A
git commit --quiet -m "main: divergent conflict content"

# Merge — expected to fail; leaves unresolved entries in the index.
set +e
git merge --no-edit other >/dev/null 2>&1
merge_rc=$?
set -e
if [[ $merge_rc -eq 0 ]]; then
	echo "WARNING: merge unexpectedly succeeded — conflict cases are missing."
fi

# Re-materialise UU-diff3.lua with diff3-style conflict markers so the
# `|||||||` common-ancestor band exists for the conflict highlighter to
# render. `git merge-file` overwrites the working file in place using the
# three blob inputs we extract from the merge index.
diff3_path="$CONFLICTS_DIR/UU-diff3.lua"
base_blob=$(git ls-files -u "$diff3_path" | awk '$3==1 {print $2; exit}')
ours_blob=$(git ls-files -u "$diff3_path" | awk '$3==2 {print $2; exit}')
theirs_blob=$(git ls-files -u "$diff3_path" | awk '$3==3 {print $2; exit}')
if [[ -n "$base_blob" && -n "$ours_blob" && -n "$theirs_blob" ]]; then
	ours_tmp=$(mktemp)
	base_tmp=$(mktemp)
	theirs_tmp=$(mktemp)
	git cat-file -p "$ours_blob"   > "$ours_tmp"
	git cat-file -p "$base_blob"   > "$base_tmp"
	git cat-file -p "$theirs_blob" > "$theirs_tmp"
	git merge-file --diff3 -L HEAD -L base -L other \
		"$ours_tmp" "$base_tmp" "$theirs_tmp" >/dev/null || true
	cp "$ours_tmp" "$diff3_path"
	rm -f "$ours_tmp" "$base_tmp" "$theirs_tmp"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: now layer the non-conflict working states on top of the merge.
# All operations here are pure index/worktree edits — no branch switching.
#
# Mutations append `-- comment` lines so the working files remain valid Lua
# even after multiple rounds of edits — keeps the diff readable in nvim.
# ─────────────────────────────────────────────────────────────────────────────

# M.  staged-modified
echo "-- TODO(staged): tweak tag" >> "$FILES_DIR/modified-staged.lua"
git add "$FILES_DIR/modified-staged.lua"

# .M  unstaged-modified
echo "-- TODO(unstaged): tweak tag" >> "$FILES_DIR/modified-unstaged.lua"

# A.  staged-added
write_module "$FILES_DIR/added-staged.lua" "added-staged"
git add "$FILES_DIR/added-staged.lua"

# D.  staged-deleted
git rm --quiet "$FILES_DIR/deleted-staged.lua"

# .D  unstaged-deleted
rm "$FILES_DIR/deleted-unstaged.lua"

# R.  staged-rename
git mv "$FILES_DIR/renamed-old.lua" "$FILES_DIR/renamed-new.lua"

# C.  staged-copy. Copy detection only triggers when the source also appears
# in the diff — touch copy-source.lua minimally so git pairs them.
cp "$FILES_DIR/copy-source.lua" "$FILES_DIR/copied-new.lua"
echo "-- trailing edit to trigger copy detection" >> "$FILES_DIR/copy-source.lua"
git add "$FILES_DIR/copied-new.lua" "$FILES_DIR/copy-source.lua"

# ?   untracked
write_module "$FILES_DIR/untracked.lua" "untracked"

# !   ignored
echo "ignored log line" > "$FILES_DIR/ignored.log"

# MM  modified staged + modified again in worktree
echo "-- staged change for MM" >> "$FILES_DIR/both-MM.lua"
git add "$FILES_DIR/both-MM.lua"
echo "-- and one more unstaged change for MM" >> "$FILES_DIR/both-MM.lua"

# AM  added staged + modified in worktree
write_module "$FILES_DIR/both-AM.lua" "both-AM"
git add "$FILES_DIR/both-AM.lua"
echo "-- modified after add (AM)" >> "$FILES_DIR/both-AM.lua"

# AD  added staged + deleted in worktree
write_module "$FILES_DIR/both-AD.lua" "both-AD"
git add "$FILES_DIR/both-AD.lua"
rm "$FILES_DIR/both-AD.lua"

# MD  modified staged + deleted in worktree
echo "-- staged change for MD" >> "$FILES_DIR/both-MD.lua"
git add "$FILES_DIR/both-MD.lua"
rm "$FILES_DIR/both-MD.lua"

# RM  renamed + modified in worktree
git mv "$FILES_DIR/both-RM-old.lua" "$FILES_DIR/both-RM-new.lua"
echo "-- post-rename edit (RM)" >> "$FILES_DIR/both-RM-new.lua"

# A stray ignored file at the repo root for good measure.
echo "ds-store" > .DS_Store

# ─────────────────────────────────────────────────────────────────────────────
# Done. Print a summary.
# ─────────────────────────────────────────────────────────────────────────────
echo
echo "Test repo ready at: $DEST"
echo
echo "Open in nvim with:"
echo "  nvim -u $DEST/init.lua $DEST/$CONFLICTS_DIR/UU.lua"
echo
echo "Summary (porcelain v1 for quick scanning):"
git -C "$DEST" -c color.status=never status --porcelain=v1 --ignored \
	| awk '{ printf "  %s\n", $0 }'
echo
echo "Full porcelain v2 dump:"
echo "  git -C $DEST status --porcelain=v2 --ignored -z | tr '\\0' '\\n'"
