#!/usr/bin/env bash
# find_repo_root.sh [dir]
#
# Print the absolute path of the enclosing git repository's top-level directory.
# Exit codes:
#   0 + path on stdout: located the repo root.
#   1 (no stdout, message on stderr): no enclosing git repository.

set -euo pipefail

start_dir="${1:-$PWD}"

if ! cd "$start_dir" 2>/dev/null; then
  echo "find_repo_root: directory not found: $start_dir" >&2
  exit 1
fi

if ! root=$(git rev-parse --show-toplevel 2>/dev/null); then
  echo "find_repo_root: not inside a git repository (start: $start_dir)" >&2
  exit 1
fi

echo "$root"
