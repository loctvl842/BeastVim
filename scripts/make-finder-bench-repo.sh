#!/usr/bin/env bash
# Build a throwaway *large* repo of markdown/code files to stress-test the
# finder's live_grep bigram prefilter engine. Lets you reproduce the 90k-file
# behaviour without needing a real giant repo, and compare engine on/off.
#
# Usage:
#   scripts/make-finder-bench-repo.sh [DEST] [FILE_COUNT]
#
# DEST       defaults to /tmp/beast-finder-bench-repo (wiped if it exists).
# FILE_COUNT defaults to 90000 (the size at which full-tree rg gets slow).
#
# After running:
#   cd $DEST && nvim          # then open live_grep and search
# or run the automated A/B benchmark:
#   nvim --clean --headless -l scripts/bench-grep-ab.lua   (from BeastVim dir,
#                                                           with BENCH_ROOT=$DEST)
#
# The generated files contain a known set of tokens with varying frequency so
# you can test both highly-selective queries (rare token → few survivors) and
# weakly-selective ones (common token → many survivors):
#   * "calendar", "event", "function", "authentication"  → common (many files)
#   * "zebra_marker_<n>"                                  → unique (one file)
#   * "needle_rare_token"                                 → rare (~1% of files)

set -euo pipefail

DEST="${1:-/tmp/beast-finder-bench-repo}"
FILE_COUNT="${2:-90000}"

echo "Generating $FILE_COUNT files into $DEST …"
rm -rf "$DEST"
mkdir -p "$DEST"

# Spread files across a believable directory tree so the walk has real depth.
# Token frequency is controlled inside the awk body below.

# Use awk to generate fast (shell loops over 90k files are slow).
awk -v n="$FILE_COUNT" -v dest="$DEST" '
BEGIN {
  split("api concepts reference guides tutorials includes resources samples auth graph users groups calendar mail files sites teams reports", dirs, " ");
  ndirs = 18;
  srand(42);
  for (i = 1; i <= n; i++) {
    d = dirs[int(rand()*ndirs)+1];
    subn = int(rand()*40);                     # second-level subdir
    path = dest "/" d "/sub" subn;
    fname = path "/doc_" i ".md";
    if (!(path in made)) { system("mkdir -p \"" path "\""); made[path]=1; }
    # body: common tokens always; rare/unique tokens sometimes
    print "# Document " i               > fname;
    print "The calendar event function for authentication." >> fname;
    print "User group reference for the graph event."        >> fname;
    if (i % 100 == 0) print "needle_rare_token appears here." >> fname;  # ~1%
    print "zebra_marker_" i " is unique to this file."        >> fname;  # unique
    close(fname);
    if (i % 10000 == 0) printf("  … %d files\n", i) > "/dev/stderr";
  }
}'

# Make it a real repo so rg's .gitignore handling is exercised.
( cd "$DEST" && git init -q && printf '*.log\n.DS_Store\n' > .gitignore )

ACTUAL=$(find "$DEST" -type f -name '*.md' | wc -l | tr -d ' ')
SIZE=$(du -sh "$DEST" | cut -f1)
echo "Done: $ACTUAL markdown files, $SIZE total, at $DEST"
echo
echo "Try it:"
echo "  cd $DEST && nvim   → open live_grep, search 'calendar' (common) vs 'needle_rare_token' (rare)"
echo "  Token frequency in this repo:"
echo "    calendar / event / function / authentication  → ~every file (weak prefilter)"
echo "    needle_rare_token                             → ~1% of files (strong prefilter)"
echo "    zebra_marker_<n>                              → exactly one file (maximal prefilter)"
