#!/usr/bin/env bash
# run_pmd.sh <repo-root> <ruleset>[,<ruleset>...]
#
# Run `pmd check` recursively over the repo and write a JSON report to
#   <repo-root>/.code-quality-mentor/pmd-report.json
#
# The pipeline does NOT fail when PMD finds violations — that's expected
# behaviour, not a build error.
#
# Output on stdout: the absolute path of the written report.
#
# Exit codes:
#   0 — report written.
#   1 — invalid input, missing tool, or PMD crashed (non-violation error).

set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: run_pmd.sh <repo-root> <comma-separated-rulesets>" >&2
  exit 1
fi

repo_root="$1"
rulesets="$2"

if [ ! -d "$repo_root" ]; then
  echo "run_pmd: not a directory: $repo_root" >&2
  exit 1
fi

if ! command -v pmd >/dev/null 2>&1; then
  echo "run_pmd: pmd is not on PATH" >&2
  exit 1
fi

out_dir="$repo_root/.code-quality-mentor"
mkdir -p "$out_dir"
report="$out_dir/pmd-report.json"

# --no-fail-on-violation: don't return non-zero when PMD finds warnings.
# PMD still returns non-zero on real errors (bad CLI args, parse failure on a
# rules file, etc.), which we DO want to surface.
if ! pmd check \
      --format json \
      --report-file "$report" \
      --rulesets "$rulesets" \
      --dir "$repo_root" \
      --no-fail-on-violation \
      >/dev/null 2>"$out_dir/pmd-stderr.log"; then
  echo "run_pmd: pmd exited non-zero (not a violation). See:" >&2
  echo "  $out_dir/pmd-stderr.log" >&2
  exit 1
fi

echo "$report"
