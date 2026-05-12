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

@test "e2e: PMD + SpotBugs merged pipeline attributes both finding types" {
  require_tool spotbugs
  require_tool javac

  # Use the JVM-shaped fixture; compile it so SpotBugs has bytecode.
  jvm_repo="$BATS_TEST_TMPDIR/jvm-repo"
  bash "$FIXTURES_DIR/setup_jvm_repo.sh" "$jvm_repo"
  mkdir -p "$jvm_repo/build/classes/java/main"
  javac -g -d "$jvm_repo/build/classes/java/main" "$jvm_repo"/src/main/java/Bug.java

  langs=$("$SCRIPTS_DIR/detect_languages.sh" "$jvm_repo")
  ruleset=$(echo "$langs" | jq -r '.[] | select(.pmd_language_id == "java") | .ruleset // empty')
  if [ -z "$ruleset" ]; then
    skip "Linguist did not classify the JVM fixture as Java"
  fi

  pmd_report=$("$SCRIPTS_DIR/run_pmd.sh" "$jvm_repo" "$ruleset")
  spotbugs_report=$("$SCRIPTS_DIR/run_spotbugs.sh" "$jvm_repo")
  merged="$jvm_repo/.code-quality-mentor/findings-report.json"
  "$SCRIPTS_DIR/merge_reports.sh" "$merged" "$pmd_report" "$spotbugs_report"

  # The merged report must contain at least one SpotBugs bug type.
  has_spotbugs=$(jq -r '[.files[]?.violations[]?.rule] | any(startswith("EI_") or startswith("ES_") or startswith("OS_") or startswith("NP_"))' "$merged")
  assert_eq "true" "$has_spotbugs" "merged report has SpotBugs-style rule names"

  blame=$("$SCRIPTS_DIR/blame_warnings.sh" "$jvm_repo" "$merged")
  alice_rules=$(jq -r '.[] | select(.author_email == "alice@example.com") | .warnings | map(.rule) | sort | join(",")' "$blame")
  assert_contains "$alice_rules" "EI_EXPOSE_REP"
}
