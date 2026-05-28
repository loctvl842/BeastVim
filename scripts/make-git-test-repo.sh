#!/usr/bin/env bash
# Build a throwaway git repo that exercises every porcelain v2 status case
# the BeastVim explorer cares about.
#
# Usage:
#   scripts/make-git-test-repo.sh [DEST]
#
# DEST defaults to /tmp/beast-git-test-repo. The directory is wiped if it
# exists. After running, inspect with:
#   git -C $DEST status --porcelain=v2 --ignored -z | tr '\0' '\n'
#
# Cases produced (XY column = porcelain v1 shorthand):
#
#   Single-axis (one side dirty):
#     M.  staged-modified           files/modified-staged.txt
#     .M  unstaged-modified         files/modified-unstaged.txt
#     A.  staged-added              files/added-staged.txt
#     D.  staged-deleted            files/deleted-staged.txt
#     .D  unstaged-deleted          files/deleted-unstaged.txt
#     R.  staged-renamed            files/renamed-new.txt  (from renamed-old.txt)
#     C.  staged-copied             files/copied-new.txt   (from copy-source.txt) *
#     ?   untracked                 files/untracked.txt
#     !   ignored                   files/ignored.log
#
#   Both axes (phase = "both"):
#     MM  modified staged + modified again        files/both-MM.txt
#     AM  added staged + modified in worktree     files/both-AM.txt
#     AD  added staged + deleted in worktree      files/both-AD.txt
#     MD  modified staged + deleted in worktree   files/both-MD.txt
#     RM  renamed + modified                       files/both-RM-new.txt
#
#   Conflicts (u record):
#     UU  both modified                            conflicts/UU.txt
#     AA  both added                               conflicts/AA.txt
#     DU  deleted by us, modified by them          conflicts/DU.txt
#     UD  modified by us, deleted by them          conflicts/UD.txt
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

mkdir -p files conflicts

# .gitignore so we can produce ignored entries later.
cat > .gitignore <<'EOF'
*.log
.DS_Store
EOF

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: baseline commit. Includes the files step-2 will mutate AND the
# pre-existing files that the conflict step needs both branches to share.
# ─────────────────────────────────────────────────────────────────────────────
echo "baseline modified-staged"   > files/modified-staged.txt
echo "baseline modified-unstaged" > files/modified-unstaged.txt
echo "baseline deleted-staged"    > files/deleted-staged.txt
echo "baseline deleted-unstaged"  > files/deleted-unstaged.txt
echo "baseline renamed-old"       > files/renamed-old.txt
echo "baseline both-MM"            > files/both-MM.txt
echo "baseline both-MD"            > files/both-MD.txt
echo "baseline both-RM-old"        > files/both-RM-old.txt

# Source for a copy. Long enough that git's copy detector accepts it.
cat > files/copy-source.txt <<'EOF'
This file is the copy source. It has enough content that git's
similarity detector will treat a near-identical sibling as a copy
rather than a fresh add.
Line three.
Line four.
EOF

# Files for the conflict step that must exist on both branches.
echo "baseline UU"            > conflicts/UU.txt
echo "baseline DU"            > conflicts/DU.txt
echo "baseline UD"            > conflicts/UD.txt

echo "README" > README.md

git add .
git commit --quiet -m "baseline"

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: build the conflict scenarios FIRST (before any working-tree dirt).
#
# Branch `other` makes one side of every conflict, main makes the other,
# then we merge `other` into main and leave the result unresolved.
# ─────────────────────────────────────────────────────────────────────────────
git checkout --quiet -b other

# UU  both modified (file existed on baseline; both branches modify it)
echo "from other" > conflicts/UU.txt
# AA  both added (file new to both branches with different content)
echo "from other" > conflicts/AA.txt
# DU  deleted by us / modified by them — main will delete, other modifies
echo "them-modified" > conflicts/DU.txt
# UD  modified by us / deleted by them — other deletes, main modifies
git rm --quiet conflicts/UD.txt

git add -A
git commit --quiet -m "other-branch changes"

# Back to main and apply our side.
git checkout --quiet main

echo "modified on main" > conflicts/UU.txt
echo "from main"        > conflicts/AA.txt
git rm --quiet            conflicts/DU.txt
echo "us-modified"      > conflicts/UD.txt

git add -A
git commit --quiet -m "main-branch changes"

# Merge — expected to fail; leaves unresolved entries in the index.
set +e
git merge --no-edit other >/dev/null 2>&1
merge_rc=$?
set -e
if [[ $merge_rc -eq 0 ]]; then
	echo "WARNING: merge unexpectedly succeeded — conflict cases are missing."
fi

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: now layer the non-conflict working states on top of the merge.
# All operations here are pure index/worktree edits — no branch switching.
# ─────────────────────────────────────────────────────────────────────────────

# M.  staged-modified
echo "staged change" >> files/modified-staged.txt
git add files/modified-staged.txt

# .M  unstaged-modified
echo "unstaged change" >> files/modified-unstaged.txt

# A.  staged-added
echo "new" > files/added-staged.txt
git add files/added-staged.txt

# D.  staged-deleted
git rm --quiet files/deleted-staged.txt

# .D  unstaged-deleted
rm files/deleted-unstaged.txt

# R.  staged-rename
git mv files/renamed-old.txt files/renamed-new.txt

# C.  staged-copy. Copy detection only triggers when the source also appears
# in the diff — touch copy-source.txt minimally so git pairs them.
cp files/copy-source.txt files/copied-new.txt
echo "# trailing edit to trigger copy detection" >> files/copy-source.txt
git add files/copied-new.txt files/copy-source.txt

# ?   untracked
echo "untracked" > files/untracked.txt

# !   ignored
echo "ignored" > files/ignored.log

# MM  modified staged + modified again in worktree
echo "staged"             >> files/both-MM.txt
git add files/both-MM.txt
echo "and more unstaged"  >> files/both-MM.txt

# AM  added staged + modified in worktree
echo "added" > files/both-AM.txt
git add files/both-AM.txt
echo "modified after add" >> files/both-AM.txt

# AD  added staged + deleted in worktree
echo "added" > files/both-AD.txt
git add files/both-AD.txt
rm files/both-AD.txt

# MD  modified staged + deleted in worktree
echo "staged change" >> files/both-MD.txt
git add files/both-MD.txt
rm files/both-MD.txt

# RM  renamed + modified in worktree
git mv files/both-RM-old.txt files/both-RM-new.txt
echo "post-rename edit" >> files/both-RM-new.txt

# A stray ignored file at the repo root for good measure.
echo "ds-store" > .DS_Store

# ─────────────────────────────────────────────────────────────────────────────
# Done. Print a summary.
# ─────────────────────────────────────────────────────────────────────────────
echo
echo "Test repo ready at: $DEST"
echo
echo "Summary (porcelain v1 for quick scanning):"
git -C "$DEST" -c color.status=never status --porcelain=v1 --ignored \
	| awk '{ printf "  %s\n", $0 }'
echo
echo "Full porcelain v2 dump:"
echo "  git -C $DEST status --porcelain=v2 --ignored -z | tr '\\0' '\\n'"
