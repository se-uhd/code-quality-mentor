#!/usr/bin/env bats

load 'test_helper'

setup() {
  require_tool git
  require_tool jq
  require_tool awk
  require_tool java
  require_tool pmd
  if ! command -v github-linguist >/dev/null 2>&1 && \
     ! command -v enry >/dev/null 2>&1; then
    skip "neither github-linguist nor enry on PATH"
  fi
  REPO_DIR="$BATS_TEST_TMPDIR/repo"
  bash "$FIXTURES_DIR/setup_tiny_java_repo.sh" "$REPO_DIR"
}

@test "e2e: PMD pipeline produces a blame-attributed report" {
  langs=$("$SCRIPTS_DIR/detect_languages.sh" "$REPO_DIR")
  java_present=$(echo "$langs" | jq '[.[].pmd_language_id] | index("java") != null')
  if [ "$java_present" != "true" ]; then
    skip "Linguist on this host did not classify the synthetic repo as Java"
  fi

  ruleset=$(echo "$langs" | jq -r '.[] | select(.pmd_language_id == "java") | .ruleset')
  pmd_report=$("$SCRIPTS_DIR/run_pmd.sh" "$REPO_DIR" "$ruleset")
  [ -f "$pmd_report" ] || { echo "pmd report not written" >&2; return 1; }

  violation_count=$(jq '[.files[]?.violations[]?] | length' "$pmd_report")
  if [ "$violation_count" -eq 0 ]; then
    skip "PMD found zero violations on the synthetic repo — ruleset may have changed"
  fi

  blame_report=$("$SCRIPTS_DIR/blame_warnings.sh" "$REPO_DIR" "$pmd_report")
  [ -f "$blame_report" ] || { echo "blame report not written" >&2; return 1; }

  author_count=$(jq 'length' "$blame_report")
  [ "$author_count" -ge 2 ] || {
    echo "expected ≥2 authors, got $author_count" >&2
    jq '.' "$blame_report" >&2
    return 1
  }
  emails=$(jq -r '[.[].author_email] | sort | join(",")' "$blame_report")
  assert_contains "$emails" "alice@example.com"
  assert_contains "$emails" "bob@example.com"
}

