#!/usr/bin/env bats

load 'test_helper'

setup() {
  require_tool git
  require_tool jq
  require_tool awk

  REPO_DIR="$BATS_TEST_TMPDIR/repo"
  bash "$FIXTURES_DIR/setup_tiny_java_repo.sh" "$REPO_DIR"

  # Hand-rolled PMD report whose filenames point at the tempdir we just built.
  REPORT="$REPO_DIR/.code-quality-mentor/pmd-report.json"
  mkdir -p "$(dirname "$REPORT")"
  cat > "$REPORT" <<EOF
{
  "formatVersion": 0,
  "pmdVersion": "7.0.0",
  "files": [
    {
      "filename": "$REPO_DIR/src/Foo.java",
      "violations": [
        {"beginline": 3, "endline": 3, "rule": "UnusedLocalVariable", "description": "Avoid unused local 'unused'."},
        {"beginline": 6, "endline": 8, "rule": "EmptyCatchBlock", "description": "Avoid empty catch blocks."}
      ]
    },
    {
      "filename": "$REPO_DIR/src/Bar.java",
      "violations": [
        {"beginline": 6, "endline": 6, "rule": "AvoidPrintStackTrace", "description": "Avoid printStackTrace."}
      ]
    },
    {
      "filename": "$REPO_DIR/src/Baz.java",
      "violations": [
        {"beginline": 5, "endline": 5, "rule": "EmptyCatchBlock", "description": "Avoid empty catch blocks."}
      ]
    }
  ]
}
EOF
}

@test "blame_warnings.sh: aggregates warnings by author email" {
  run "$SCRIPTS_DIR/blame_warnings.sh" "$REPO_DIR"
  assert_eq 0 "$status" "exit code"

  out="$REPO_DIR/.code-quality-mentor/blame-report.json"
  [ -f "$out" ] || { echo "report not written: $out" >&2; return 1; }

  count=$(jq 'length' "$out")
  assert_eq 2 "$count" "author count"

  # Both authors have 2 warnings each.
  alice_count=$(jq '.[] | select(.author_email == "alice@example.com") | .warning_count' "$out")
  bob_count=$(jq '.[] | select(.author_email == "bob@example.com") | .warning_count' "$out")
  assert_eq 2 "$alice_count" "alice warning_count"
  assert_eq 2 "$bob_count" "bob warning_count"
}

@test "blame_warnings.sh: preserves rule names and line numbers per warning" {
  run "$SCRIPTS_DIR/blame_warnings.sh" "$REPO_DIR"
  assert_eq 0 "$status" "exit code"
  out="$REPO_DIR/.code-quality-mentor/blame-report.json"

  alice_rules=$(jq -r '.[] | select(.author_email == "alice@example.com") | .warnings | map(.rule) | sort | .[]' "$out" | paste -sd, -)
  assert_eq "EmptyCatchBlock,UnusedLocalVariable" "$alice_rules" "alice rules"

  bob_rules=$(jq -r '.[] | select(.author_email == "bob@example.com") | .warnings | map(.rule) | sort | .[]' "$out" | paste -sd, -)
  assert_eq "AvoidPrintStackTrace,EmptyCatchBlock" "$bob_rules" "bob rules"
}

@test "blame_warnings.sh: uses email as canonical key (display name preserved)" {
  run "$SCRIPTS_DIR/blame_warnings.sh" "$REPO_DIR"
  assert_eq 0 "$status" "exit code"
  out="$REPO_DIR/.code-quality-mentor/blame-report.json"

  alice_name=$(jq -r '.[] | select(.author_email == "alice@example.com") | .author_name' "$out")
  bob_name=$(jq -r '.[] | select(.author_email == "bob@example.com") | .author_name' "$out")
  assert_eq "Alice Example" "$alice_name" "alice name"
  assert_eq "Bob Builder" "$bob_name" "bob name"
}

@test "blame_warnings.sh: empty PMD report yields empty author array" {
  empty_report="$REPO_DIR/.code-quality-mentor/empty.json"
  echo '{"files":[]}' > "$empty_report"
  run "$SCRIPTS_DIR/blame_warnings.sh" "$REPO_DIR" "$empty_report"
  assert_eq 0 "$status" "exit code"
  out=$(cat "$REPO_DIR/.code-quality-mentor/blame-report.json")
  assert_eq "[]" "$out" "empty array"
}

@test "blame_warnings.sh: warnings on deleted files are silently dropped" {
  ghost_report="$REPO_DIR/.code-quality-mentor/ghost.json"
  cat > "$ghost_report" <<EOF
{
  "files": [
    {"filename": "$REPO_DIR/src/Nonexistent.java", "violations": [
      {"beginline": 1, "endline": 1, "rule": "FakeRule", "description": "x"}
    ]}
  ]
}
EOF
  run "$SCRIPTS_DIR/blame_warnings.sh" "$REPO_DIR" "$ghost_report"
  assert_eq 0 "$status" "exit code"
  out=$(cat "$REPO_DIR/.code-quality-mentor/blame-report.json")
  assert_eq "[]" "$out" "deleted-file warning dropped"
}

@test "blame_warnings.sh: rejects a missing repo path" {
  run "$SCRIPTS_DIR/blame_warnings.sh" "$BATS_TEST_TMPDIR/does-not-exist"
  assert_eq 1 "$status" "exit code"
  assert_contains "$output" "not a directory"
}

@test "blame_warnings.sh: rejects a missing PMD report" {
  empty_repo="$BATS_TEST_TMPDIR/empty-repo"
  mkdir -p "$empty_repo"
  run "$SCRIPTS_DIR/blame_warnings.sh" "$empty_repo"
  assert_eq 1 "$status" "exit code"
  assert_contains "$output" "findings report not found"
}
