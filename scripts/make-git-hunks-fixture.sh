#!/usr/bin/env bash
# Build a throwaway git repo with a single file that exercises every git
# hunk type the BeastVim statuscolumn cares about:
#
#   add           — new lines inserted (no baseline counterpart)
#   change        — existing lines modified
#   delete        — lines removed (sign placed on line *above* the deletion)
#   topdelete     — file's first line removed (sign on line 1)
#   changedelete  — a change hunk where more lines were removed than added
#
# Usage:
#   scripts/make-git-hunks-fixture.sh [DEST]
#
# DEST defaults to /tmp/beast-git-hunks-fixture. Open `sample.txt` in nvim
# to see all five sign types in the statuscolumn, plus exercise
# <leader>gp / ]c / [c.
set -euo pipefail

DEST="${1:-/tmp/beast-git-hunks-fixture}"

if [[ -e "$DEST" ]]; then
	echo "Removing existing $DEST"
	rm -rf "$DEST"
fi

mkdir -p "$DEST"
cd "$DEST"

git init --quiet --initial-branch=main
git config user.email "test@beastvim.local"
git config user.name "BeastVim Test"
git config commit.gpgsign false

# ─────────────────────────────────────────────────────────────────────────────
# Baseline: a 30-line file with predictable, numbered content.
# ─────────────────────────────────────────────────────────────────────────────
{
	for i in $(seq 1 30); do
		printf 'line %02d — baseline\n' "$i"
	done
} > sample.txt

git add sample.txt
git commit --quiet -m "baseline sample.txt"

# ─────────────────────────────────────────────────────────────────────────────
# Worktree edits — each chunk targets one sign type.
#
# Final layout (worktree line numbers shown):
#   topdelete    on line  1   (baseline line 1 deleted)
#   change       on line  4   (baseline line 5 modified in place)
#   add          on lines 10–12 (3 brand-new lines)
#   delete       on line 19   (baseline line 18 removed; sign sits on line above)
#   changedelete on line 24   (baseline lines 23–25 collapsed into 1 line)
# ─────────────────────────────────────────────────────────────────────────────
python3 - <<'PY'
from pathlib import Path

src = Path("sample.txt").read_text().splitlines()
out = []

# Skip baseline line 1 → topdelete on new line 1.
for idx, line in enumerate(src, start=1):
	if idx == 1:
		continue
	if idx == 5:
		out.append("line 05 — MODIFIED (change)")
		continue
	if idx == 18:
		# Drop this line entirely → pure delete hunk.
		continue
	if idx == 23:
		# Replace 3 baseline lines (23,24,25) with a single line → changedelete.
		out.append("line 23 — COLLAPSED three lines into one (changedelete)")
		continue
	if idx in (24, 25):
		continue
	out.append(line)
	if idx == 10:
		# Inject 3 brand-new lines → pure add hunk.
		out.append("line ++ — ADDED A")
		out.append("line ++ — ADDED B")
		out.append("line ++ — ADDED C")

Path("sample.txt").write_text("\n".join(out) + "\n")
PY

echo
echo "Fixture ready at: $DEST/sample.txt"
echo
echo "Open it with:"
echo "  nvim $DEST/sample.txt"
echo
echo "Expected statuscolumn signs (worktree line numbers):"
echo "   1  topdelete"
echo "   4  change"
echo "  10  add"
echo "  11  add"
echo "  12  add"
echo "  16  delete"
echo "  23  changedelete"
echo
echo "Diff preview:"
git -c color.diff=never diff --unified=0 sample.txt | sed 's/^/  /'
