#!/usr/bin/env bash
# run.sh — entrypoint for the bats test suite.
#
# Runs every *.bats file under this directory. Exits non-zero if any test
# fails. Tests that require a tool not on PATH skip themselves with a notice;
# the suite as a whole still passes when only the host-dependent layers skip.

set -euo pipefail

if ! command -v bats >/dev/null 2>&1; then
  echo "run.sh: bats is not on PATH" >&2
  echo "install: 'brew install bats-core' (macOS) or follow https://bats-core.readthedocs.io/" >&2
  exit 2
fi

cd "$(dirname "$0")"
exec bats .
