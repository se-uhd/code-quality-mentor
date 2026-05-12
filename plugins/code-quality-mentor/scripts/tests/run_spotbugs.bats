#!/usr/bin/env bats

load 'test_helper'

# run_spotbugs.bats is layer-3: the script *runs* spotbugs against compiled
# bytecode. We require git/jq/awk/java/javac/spotbugs; otherwise the test
# skips cleanly so the rest of the suite still runs on lightweight hosts.

setup() {
  require_tool git
  require_tool jq
  require_tool awk
  require_tool javac
  require_tool spotbugs

  REPO="$BATS_TEST_TMPDIR/jvm-repo"
  bash "$FIXTURES_DIR/setup_jvm_repo.sh" "$REPO"
  mkdir -p "$REPO/build/classes/java/main"
  javac -g -d "$REPO/build/classes/java/main" "$REPO"/src/main/java/Bug.java
}

@test "run_spotbugs.sh: writes a PMD-shape report with real bug types" {
  run "$SCRIPTS_DIR/run_spotbugs.sh" "$REPO"
  assert_eq 0 "$status" "exit code"

  report="$REPO/.code-quality-mentor/spotbugs-report.json"
  [ -f "$report" ] || { echo "report not written" >&2; return 1; }

  # Top-level shape mirrors PMD's JSON output.
  has_files=$(jq -r 'has("files")' "$report")
  assert_eq "true" "$has_files" "files key present"

  # We expect at least two findings on Bug.java (EI_EXPOSE_REP, ES_*).
  v_count=$(jq '[.files[]?.violations[]?] | length' "$report")
  [ "$v_count" -ge 2 ] || {
    echo "expected ≥2 violations, got $v_count" >&2
    jq '.' "$report" >&2
    return 1
  }

  # Rule names should be SpotBugs bug types (uppercase with underscores).
  rules=$(jq -r '[.files[]?.violations[]?.rule] | sort | unique | join(",")' "$report")
  assert_contains "$rules" "EI_EXPOSE_REP"
}

@test "run_spotbugs.sh: rule entries carry beginline, endline, ruleset, priority" {
  run "$SCRIPTS_DIR/run_spotbugs.sh" "$REPO"
  assert_eq 0 "$status" "exit code"
  report="$REPO/.code-quality-mentor/spotbugs-report.json"

  missing=$(jq -r '
    [.files[]?.violations[]?
      | select(
          (.beginline == null) or (.endline == null) or
          (.rule == null) or (.ruleset == null) or (.priority == null)
        )]
      | length
  ' "$report")
  assert_eq 0 "$missing" "violations missing required fields"
}

@test "run_spotbugs.sh: filename in report is an existing absolute path" {
  run "$SCRIPTS_DIR/run_spotbugs.sh" "$REPO"
  assert_eq 0 "$status" "exit code"
  report="$REPO/.code-quality-mentor/spotbugs-report.json"

  filenames=$(jq -r '.files[].filename' "$report")
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -f "$f" ] || { echo "filename does not exist: $f" >&2; return 1; }
  done <<< "$filenames"
}

@test "run_spotbugs.sh: exits 2 when no compiled bytecode is present" {
  rm -rf "$REPO/build"
  run "$SCRIPTS_DIR/run_spotbugs.sh" "$REPO"
  assert_eq 2 "$status" "exit code"
  assert_contains "$output" "no compiled bytecode"
}

@test "run_spotbugs.sh: rejects a missing repo path" {
  run "$SCRIPTS_DIR/run_spotbugs.sh" "$BATS_TEST_TMPDIR/does-not-exist"
  assert_eq 1 "$status" "exit code"
  assert_contains "$output" "not a directory"
}
