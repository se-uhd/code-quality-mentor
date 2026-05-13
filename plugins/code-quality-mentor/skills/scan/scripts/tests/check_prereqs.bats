#!/usr/bin/env bats

load 'test_helper'

@test "check_prereqs.sh: empty PATH lists every missing tool" {
  # Point PATH at an empty directory so `command -v` finds nothing, while
  # keeping the rest of the environment intact so bash itself still launches.
  empty_dir="$BATS_TEST_TMPDIR/empty"
  mkdir -p "$empty_dir"
  # Invoke bash by absolute path ($BASH) so that the empty PATH does not
  # prevent the interpreter itself from being located.
  PATH="$empty_dir" run "$BASH" "$SCRIPTS_DIR/check_prereqs.sh"
  assert_eq 1 "$status" "exit code"
  assert_contains "$output" "missing: java"
  assert_contains "$output" "missing: pmd"
  assert_contains "$output" "missing: jq"
  assert_contains "$output" "missing: git"
  assert_contains "$output" "missing: github-linguist OR enry"
}

@test "check_prereqs.sh: succeeds when every required tool is present" {
  # Sanity check on the host. If anything is genuinely missing, skip — this
  # test is about the script's success path, not about the host's setup.
  for t in java pmd jq git; do
    command -v "$t" >/dev/null 2>&1 || skip "host is missing $t — not a script bug"
  done
  if ! command -v github-linguist >/dev/null 2>&1 && \
     ! command -v enry >/dev/null 2>&1; then
    skip "host is missing both github-linguist and enry — not a script bug"
  fi
  run "$SCRIPTS_DIR/check_prereqs.sh"
  assert_eq 0 "$status" "exit code"
}
