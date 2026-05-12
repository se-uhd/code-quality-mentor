#!/usr/bin/env bats

# Unit tests for the standalone XML→PMD-JSON converter. The fixture
# `spotbugs_sample_output.xml` is a real captured `spotbugs -xml:withMessages`
# output containing two bug instances (EI_EXPOSE_REP, ES_COMPARING_PARAMETER_STRING_WITH_EQ).
# This test does NOT require spotbugs or javac to be installed — only jq + awk.

load 'test_helper'

setup() {
  require_tool jq
  require_tool awk

  WORK="$BATS_TEST_TMPDIR/work"
  mkdir -p "$WORK"

  # Recreate the source directory structure referenced by the fixture XML's
  # <SourceLine sourcepath="Bug.java"> entries, so path resolution succeeds.
  mkdir -p "$WORK/src"
  cat > "$WORK/src/Bug.java" <<'EOF'
public class Bug {
    private int[] secret = new int[10];

    public int[] getSecret() {
        return secret;
    }

    public boolean equalStrings(String a, String b) {
        return a == b;
    }
}
EOF
}

@test "spotbugs_xml_to_pmd.sh: emits PMD-shape JSON from the captured fixture" {
  run "$SCRIPTS_DIR/spotbugs_xml_to_pmd.sh" \
    "$FIXTURES_DIR/spotbugs_sample_output.xml" \
    "$WORK/src"
  assert_eq 0 "$status" "exit code"

  # Shape check.
  has_files=$(echo "$output" | jq -r 'has("files")')
  assert_eq "true" "$has_files" "files key present"

  v_count=$(echo "$output" | jq '[.files[].violations[]] | length')
  assert_eq 2 "$v_count" "violation count"
}

@test "spotbugs_xml_to_pmd.sh: extracts both EI_EXPOSE_REP and ES_COMPARING_* rules" {
  run "$SCRIPTS_DIR/spotbugs_xml_to_pmd.sh" \
    "$FIXTURES_DIR/spotbugs_sample_output.xml" \
    "$WORK/src"
  assert_eq 0 "$status" "exit code"

  rules=$(echo "$output" | jq -r '[.files[].violations[].rule] | sort | join(",")')
  assert_contains "$rules" "EI_EXPOSE_REP"
  assert_contains "$rules" "ES_COMPARING_PARAMETER_STRING_WITH_EQ"
}

@test "spotbugs_xml_to_pmd.sh: resolves sourcepaths to absolute paths under the source dir" {
  run "$SCRIPTS_DIR/spotbugs_xml_to_pmd.sh" \
    "$FIXTURES_DIR/spotbugs_sample_output.xml" \
    "$WORK/src"
  assert_eq 0 "$status" "exit code"

  filename=$(echo "$output" | jq -r '.files[0].filename')
  expected="$WORK/src/Bug.java"
  # Compare canonicalized paths (macOS may add /private prefix on tempdirs).
  assert_eq "$(cd "$(dirname "$filename")" && pwd -P)/$(basename "$filename")" \
            "$(cd "$(dirname "$expected")" && pwd -P)/$(basename "$expected")" \
            "absolute path"
}

@test "spotbugs_xml_to_pmd.sh: drops bugs whose source path cannot be resolved" {
  empty_dir="$BATS_TEST_TMPDIR/no-source"
  mkdir -p "$empty_dir"
  run "$SCRIPTS_DIR/spotbugs_xml_to_pmd.sh" \
    "$FIXTURES_DIR/spotbugs_sample_output.xml" \
    "$empty_dir"
  assert_eq 0 "$status" "exit code"
  v_count=$(echo "$output" | jq '[.files[]?.violations[]?] | length')
  assert_eq 0 "$v_count" "all bugs dropped (no source dir matched)"
}

@test "spotbugs_xml_to_pmd.sh: every violation has all required fields" {
  run "$SCRIPTS_DIR/spotbugs_xml_to_pmd.sh" \
    "$FIXTURES_DIR/spotbugs_sample_output.xml" \
    "$WORK/src"
  assert_eq 0 "$status" "exit code"

  missing=$(echo "$output" | jq -r '
    [.files[].violations[]
      | select(
          (.beginline == null) or (.endline == null) or
          (.rule == null) or (.ruleset == null) or
          (.priority == null) or (.description == null)
        )]
      | length
  ')
  assert_eq 0 "$missing" "violations missing fields"
}

@test "spotbugs_xml_to_pmd.sh: rejects missing XML file" {
  run "$SCRIPTS_DIR/spotbugs_xml_to_pmd.sh" \
    "$BATS_TEST_TMPDIR/does-not-exist.xml" \
    "$WORK/src"
  assert_eq 1 "$status" "exit code"
  assert_contains "$output" "not a file"
}

@test "spotbugs_xml_to_pmd.sh: requires at least one source dir" {
  run "$SCRIPTS_DIR/spotbugs_xml_to_pmd.sh" \
    "$FIXTURES_DIR/spotbugs_sample_output.xml"
  assert_eq 1 "$status" "exit code"
}
