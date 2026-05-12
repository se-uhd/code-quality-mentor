#!/usr/bin/env bats

load 'test_helper'

setup() {
  require_tool jq
  WORK="$BATS_TEST_TMPDIR/work"
  mkdir -p "$WORK"
  PMD_R="$WORK/pmd.json"
  SB_R="$WORK/sb.json"
  OUT="$WORK/merged.json"

  cat > "$PMD_R" <<'EOF'
{
  "formatVersion": 0,
  "pmdVersion": "7.x",
  "files": [
    {"filename": "/repo/A.java", "violations": [
      {"beginline": 3, "endline": 3, "rule": "UnusedLocalVariable", "description": "u"}
    ]}
  ]
}
EOF
  cat > "$SB_R" <<'EOF'
{
  "formatVersion": 0,
  "pmdVersion": "spotbugs",
  "files": [
    {"filename": "/repo/A.java", "violations": [
      {"beginline": 5, "endline": 5, "rule": "EI_EXPOSE_REP", "description": "e"}
    ]},
    {"filename": "/repo/B.java", "violations": [
      {"beginline": 9, "endline": 9, "rule": "ES_COMPARING_STRINGS_WITH_EQ", "description": "s"}
    ]}
  ]
}
EOF
}

@test "merge_reports.sh: concatenates violations per file across reports" {
  run "$SCRIPTS_DIR/merge_reports.sh" "$OUT" "$PMD_R" "$SB_R"
  assert_eq 0 "$status" "exit code"
  [ -f "$OUT" ] || { echo "merged not written" >&2; return 1; }

  file_count=$(jq '.files | length' "$OUT")
  assert_eq 2 "$file_count" "file count"

  a_rules=$(jq -r '.files[] | select(.filename == "/repo/A.java") | .violations | map(.rule) | sort | join(",")' "$OUT")
  assert_eq "EI_EXPOSE_REP,UnusedLocalVariable" "$a_rules" "A.java rules"

  b_rules=$(jq -r '.files[] | select(.filename == "/repo/B.java") | .violations | map(.rule) | join(",")' "$OUT")
  assert_eq "ES_COMPARING_STRINGS_WITH_EQ" "$b_rules" "B.java rules"
}

@test "merge_reports.sh: works with a single report" {
  run "$SCRIPTS_DIR/merge_reports.sh" "$OUT" "$PMD_R"
  assert_eq 0 "$status" "exit code"
  file_count=$(jq '.files | length' "$OUT")
  assert_eq 1 "$file_count" "file count"
}

@test "merge_reports.sh: empty inputs produce an empty files array" {
  empty="$WORK/empty.json"
  echo '{"files":[]}' > "$empty"
  run "$SCRIPTS_DIR/merge_reports.sh" "$OUT" "$empty" "$empty"
  assert_eq 0 "$status" "exit code"
  file_count=$(jq '.files | length' "$OUT")
  assert_eq 0 "$file_count" "file count"
}

@test "merge_reports.sh: rejects missing report path" {
  run "$SCRIPTS_DIR/merge_reports.sh" "$OUT" "$WORK/nonexistent.json"
  assert_eq 1 "$status" "exit code"
  assert_contains "$output" "not a file"
}

@test "merge_reports.sh: requires at least one input" {
  run "$SCRIPTS_DIR/merge_reports.sh" "$OUT"
  assert_eq 1 "$status" "exit code"
}
