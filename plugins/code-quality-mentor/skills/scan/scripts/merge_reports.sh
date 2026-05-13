#!/usr/bin/env bash
# merge_reports.sh <out-path> <report1.json> [<report2.json> ...]
#
# Merge two or more PMD-shape JSON reports (each containing a top-level
# `files` array of `{filename, violations}` objects) into a single combined
# report. Violations from the same filename across reports are concatenated,
# preserving order.
#
# The output also includes a top-level `files` array of the same shape, so
# downstream consumers (e.g., blame_warnings.sh) need no changes.

set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: merge_reports.sh <out-path> <report1.json> [<report2.json> ...]" >&2
  exit 1
fi

out_path="$1"
shift

for f in "$@"; do
  if [ ! -f "$f" ]; then
    echo "merge_reports: not a file: $f" >&2
    exit 1
  fi
done

mkdir -p "$(dirname "$out_path")"

jq -s '
  {
    formatVersion: 0,
    pmdVersion: "merged",
    files: (
      [.[] | .files[]? ]
      | group_by(.filename)
      | map({
          filename: .[0].filename,
          violations: ([.[] | .violations[]?])
        })
    )
  }
' "$@" > "$out_path"

echo "$out_path"
