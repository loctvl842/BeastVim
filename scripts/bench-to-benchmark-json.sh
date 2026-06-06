#!/bin/sh
# scripts/bench-to-benchmark-json.sh
# Convert a hyperfine JSON file into the `customSmallerIsBetter` format
# consumed by github-action-benchmark.
#
# Usage: bench-to-benchmark-json.sh <hyperfine.json> [label]
#   label — prefix for metric names (default: "startup")
#
# Output (stdout): JSON array suitable for `output-file-path`.

set -eu

IN="${1:?usage: bench-to-benchmark-json.sh <hyperfine.json> [label]}"
LABEL="${2:-startup}"

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required" >&2
  exit 2
fi

jq --arg label "$LABEL" '
  .results[0] as $r |
  [
    { name: ($label + " mean"),   unit: "ms", value: ($r.mean   * 1000) },
    { name: ($label + " stddev"), unit: "ms", value: ($r.stddev * 1000) },
    { name: ($label + " min"),    unit: "ms", value: ($r.min    * 1000) },
    { name: ($label + " max"),    unit: "ms", value: ($r.max    * 1000) }
  ]
' "$IN"
