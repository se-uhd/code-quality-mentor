#!/usr/bin/env bats

load 'test_helper'

setup() {
  require_tool jq
  STUB_DIR="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$STUB_DIR"
  # The script accepts a repo-root argument but our stub ignores it; we still
  # need a real directory to pass.
  REPO_DIR="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO_DIR"
  export LINGUIST_BIN
}

@test "detect_languages.sh: matches Java and JavaScript, drops Rust/Markdown" {
  LINGUIST_BIN=$(make_fake_linguist "$STUB_DIR" github-linguist)
  export FIXTURE_FILE="$FIXTURES_DIR/linguist_sample_output.json"

  run "$SCRIPTS_DIR/detect_languages.sh" "$REPO_DIR"
  assert_eq 0 "$status" "exit code"

  # Expect exactly two entries: Java and JavaScript.
  count=$(echo "$output" | jq 'length')
  assert_eq 2 "$count" "match count"

  # Sorted by metric descending: Java (51200) > JavaScript (6144).
  first_lang=$(echo "$output" | jq -r '.[0].language')
  assert_eq "Java" "$first_lang" "first language"
  first_pmd=$(echo "$output" | jq -r '.[0].pmd_language_id')
  assert_eq "java" "$first_pmd" "first pmd_language_id"
  first_ruleset=$(echo "$output" | jq -r '.[0].ruleset')
  assert_eq "rulesets/java/quickstart.xml" "$first_ruleset" "first ruleset"

  second_lang=$(echo "$output" | jq -r '.[1].language')
  assert_eq "JavaScript" "$second_lang" "second language"
  second_pmd=$(echo "$output" | jq -r '.[1].pmd_language_id')
  assert_eq "ecmascript" "$second_pmd" "second pmd_language_id"
}

@test "detect_languages.sh: returns empty array when only unsupported langs" {
  LINGUIST_BIN=$(make_fake_linguist "$STUB_DIR" github-linguist)
  export FIXTURE_FILE="$FIXTURES_DIR/linguist_only_unsupported.json"

  run "$SCRIPTS_DIR/detect_languages.sh" "$REPO_DIR"
  assert_eq 0 "$status" "exit code"
  assert_eq "[]" "$(echo "$output" | jq -c '.')" "empty array"
}

@test "detect_languages.sh: alias matching maps JSP to Java Server Pages entry" {
  LINGUIST_BIN=$(make_fake_linguist "$STUB_DIR" github-linguist)
  export FIXTURE_FILE="$FIXTURES_DIR/linguist_jsp_alias.json"

  run "$SCRIPTS_DIR/detect_languages.sh" "$REPO_DIR"
  assert_eq 0 "$status" "exit code"

  count=$(echo "$output" | jq 'length')
  assert_eq 1 "$count" "match count"
  pmd_id=$(echo "$output" | jq -r '.[0].pmd_language_id')
  assert_eq "jsp" "$pmd_id" "pmd_language_id resolved via alias"
  # The matched name should be the alias actually present in the input.
  matched=$(echo "$output" | jq -r '.[0].language')
  assert_eq "JSP" "$matched" "matched name is the observed alias"
}

@test "detect_languages.sh: enry-style array values are counted as file counts" {
  # enry emits arrays of file paths instead of size objects.
  LINGUIST_BIN=$(make_fake_linguist "$STUB_DIR" enry)
  export FIXTURE_FILE="$FIXTURES_DIR/enry_sample_output.json"

  run "$SCRIPTS_DIR/detect_languages.sh" "$REPO_DIR"
  assert_eq 0 "$status" "exit code"

  # Should match Java (3 files) and Apex (1 file); skip Python.
  count=$(echo "$output" | jq 'length')
  assert_eq 2 "$count" "match count"

  first_lang=$(echo "$output" | jq -r '.[0].language')
  assert_eq "Java" "$first_lang" "first language by metric"
  first_metric=$(echo "$output" | jq -r '.[0].metric')
  assert_eq "3" "$first_metric" "Java file count"

  second_lang=$(echo "$output" | jq -r '.[1].language')
  assert_eq "Apex" "$second_lang" "second language"
  second_metric=$(echo "$output" | jq -r '.[1].metric')
  assert_eq "1" "$second_metric" "Apex file count"
}

@test "detect_languages.sh: empty Linguist output yields empty array" {
  LINGUIST_BIN=$(make_fake_linguist "$STUB_DIR" github-linguist)
  empty_fixture="$BATS_TEST_TMPDIR/empty.json"
  echo "{}" > "$empty_fixture"
  export FIXTURE_FILE="$empty_fixture"

  run "$SCRIPTS_DIR/detect_languages.sh" "$REPO_DIR"
  assert_eq 0 "$status" "exit code"
  assert_eq "[]" "$(echo "$output" | jq -c '.')" "empty array"
}

@test "detect_languages.sh: rejects a missing repo path" {
  LINGUIST_BIN=$(make_fake_linguist "$STUB_DIR" github-linguist)
  run "$SCRIPTS_DIR/detect_languages.sh" "$BATS_TEST_TMPDIR/does-not-exist"
  assert_eq 1 "$status" "exit code"
  assert_contains "$output" "not a directory"
}
