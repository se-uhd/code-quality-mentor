#!/usr/bin/env bats

load 'test_helper'

setup() {
  require_tool jq
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
}

@test "find_classes.sh: empty repo yields empty class_dirs and repo as source root" {
  run "$SCRIPTS_DIR/find_classes.sh" "$REPO"
  assert_eq 0 "$status" "exit code"
  count=$(echo "$output" | jq '.class_dirs | length')
  assert_eq 0 "$count" "class_dirs count"
  sources=$(echo "$output" | jq -r '.source_dirs | length')
  # At minimum, the repo root itself.
  [ "$sources" -ge 1 ]
}

@test "find_classes.sh: detects Maven target/classes when it has a .class file" {
  mkdir -p "$REPO/target/classes/com/example"
  touch "$REPO/target/classes/com/example/Foo.class"
  run "$SCRIPTS_DIR/find_classes.sh" "$REPO"
  assert_eq 0 "$status" "exit code"
  cd=$(echo "$output" | jq -r '.class_dirs[]')
  assert_contains "$cd" "$REPO/target/classes"
}

@test "find_classes.sh: ignores target/classes when there is no .class inside" {
  mkdir -p "$REPO/target/classes"
  run "$SCRIPTS_DIR/find_classes.sh" "$REPO"
  assert_eq 0 "$status" "exit code"
  count=$(echo "$output" | jq '.class_dirs | length')
  assert_eq 0 "$count" "class_dirs count"
}

@test "find_classes.sh: detects Gradle build/classes/{java,kotlin}/main" {
  mkdir -p "$REPO/build/classes/java/main" "$REPO/build/classes/kotlin/main"
  touch "$REPO/build/classes/java/main/A.class"
  touch "$REPO/build/classes/kotlin/main/B.class"
  run "$SCRIPTS_DIR/find_classes.sh" "$REPO"
  assert_eq 0 "$status" "exit code"
  count=$(echo "$output" | jq '.class_dirs | length')
  assert_eq 2 "$count" "both Gradle dirs picked up"
}

@test "find_classes.sh: surfaces JARs under build/libs and target" {
  mkdir -p "$REPO/build/libs"
  echo dummy > "$REPO/build/libs/foo.jar"
  run "$SCRIPTS_DIR/find_classes.sh" "$REPO"
  assert_eq 0 "$status" "exit code"
  has_jar=$(echo "$output" | jq -r '[.class_dirs[] | select(endswith(".jar"))] | length')
  assert_eq 1 "$has_jar" "jar count"
}

@test "find_classes.sh: surfaces standard Maven and Gradle source roots when present" {
  mkdir -p "$REPO/src/main/java" "$REPO/src/main/kotlin"
  run "$SCRIPTS_DIR/find_classes.sh" "$REPO"
  assert_eq 0 "$status" "exit code"
  has_java=$(echo "$output" | jq -r '.source_dirs | any(endswith("src/main/java"))')
  assert_eq "true" "$has_java" "src/main/java in sources"
  has_kotlin=$(echo "$output" | jq -r '.source_dirs | any(endswith("src/main/kotlin"))')
  assert_eq "true" "$has_kotlin" "src/main/kotlin in sources"
}

@test "find_classes.sh: rejects a missing directory" {
  run "$SCRIPTS_DIR/find_classes.sh" "$BATS_TEST_TMPDIR/does-not-exist"
  assert_eq 1 "$status" "exit code"
  assert_contains "$output" "not a directory"
}
