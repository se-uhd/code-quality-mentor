#!/usr/bin/env bash
# run_spotbugs.sh <repo-root>
#
# Run SpotBugs on JVM bytecode found under <repo-root> and emit a report
# shaped like PMD's JSON output, so the rest of the pipeline can ingest both
# tools' findings through the same shape.
#
# Writes:
#   <repo-root>/.code-quality-mentor/spotbugs-report.json   # PMD-shape JSON
#   <repo-root>/.code-quality-mentor/spotbugs.xml           # raw SpotBugs XML
#
# Prints the path of the JSON report on stdout.
#
# Exit codes:
#   0   — report written (may have zero violations).
#   1   — invalid input, SpotBugs missing, or analysis failed.
#   2   — no compiled bytecode found; nothing to scan. Caller can choose to
#         continue with PMD-only output.

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: run_spotbugs.sh <repo-root>" >&2
  exit 1
fi

repo_root="$1"
if [ ! -d "$repo_root" ]; then
  echo "run_spotbugs: not a directory: $repo_root" >&2
  exit 1
fi
if ! command -v spotbugs >/dev/null 2>&1; then
  echo "run_spotbugs: spotbugs is not on PATH" >&2
  exit 1
fi
for tool in jq awk find; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "run_spotbugs: $tool is not on PATH" >&2
    exit 1
  fi
done

script_dir="$(cd "$(dirname "$0")" && pwd)"
out_dir="$repo_root/.code-quality-mentor"
mkdir -p "$out_dir"
xml_report="$out_dir/spotbugs.xml"
json_report="$out_dir/spotbugs-report.json"

# --- locate compiled bytecode and source roots --------------------------
probe_json=$("$script_dir/find_classes.sh" "$repo_root")
class_count=$(echo "$probe_json" | jq '.class_dirs | length')
if [ "$class_count" -eq 0 ]; then
  echo "run_spotbugs: no compiled bytecode found under $repo_root" >&2
  echo "run_spotbugs: build the project first (e.g., 'mvn compile' or 'gradle classes')" >&2
  exit 2
fi

class_dirs=()
while IFS= read -r line; do
  [ -n "$line" ] && class_dirs+=("$line")
done < <(echo "$probe_json" | jq -r '.class_dirs[]')

source_dirs=()
while IFS= read -r line; do
  [ -n "$line" ] && source_dirs+=("$line")
done < <(echo "$probe_json" | jq -r '.source_dirs[]')

# spotbugs takes a single -sourcepath argument with colon-separated entries.
source_path=$(IFS=:; echo "${source_dirs[*]}")

# --- run spotbugs ------------------------------------------------------
if ! spotbugs \
       -textui \
       -xml:withMessages \
       -output "$xml_report" \
       -sourcepath "$source_path" \
       "${class_dirs[@]}" \
       >"$out_dir/spotbugs-stdout.log" 2>"$out_dir/spotbugs-stderr.log"; then
  echo "run_spotbugs: spotbugs exited non-zero. See:" >&2
  echo "  $out_dir/spotbugs-stderr.log" >&2
  exit 1
fi

# --- convert XML → PMD-shape JSON --------------------------------------
# Delegate the XML parsing + path resolution to a standalone script that is
# also unit-testable against a captured fixture (no spotbugs binary needed).
"$script_dir/spotbugs_xml_to_pmd.sh" "$xml_report" "${source_dirs[@]}" > "$json_report"

echo "$json_report"
