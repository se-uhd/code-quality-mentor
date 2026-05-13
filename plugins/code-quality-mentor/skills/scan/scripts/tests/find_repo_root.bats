#!/usr/bin/env bats

load 'test_helper'

@test "find_repo_root.sh: exits 1 with message outside a repo" {
  tmp="$BATS_TEST_TMPDIR/nogit"
  mkdir -p "$tmp"
  run "$SCRIPTS_DIR/find_repo_root.sh" "$tmp"
  assert_eq 1 "$status" "exit code"
  assert_contains "$output" "not inside a git repository"
}

@test "find_repo_root.sh: prints repo top-level inside a repo" {
  require_tool git
  tmp="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$tmp/sub/dir"
  ( cd "$tmp" && git init -q -b main 2>/dev/null || git init -q )
  run "$SCRIPTS_DIR/find_repo_root.sh" "$tmp/sub/dir"
  assert_eq 0 "$status" "exit code"
  # macOS may prefix /private to /var, so compare canonical paths.
  expected="$(cd "$tmp" && pwd -P)"
  actual="$(cd "$output" && pwd -P)"
  assert_eq "$expected" "$actual" "repo root"
}

@test "find_repo_root.sh: fails fast on a missing directory" {
  run "$SCRIPTS_DIR/find_repo_root.sh" "$BATS_TEST_TMPDIR/does-not-exist"
  assert_eq 1 "$status" "exit code"
  assert_contains "$output" "directory not found"
}
