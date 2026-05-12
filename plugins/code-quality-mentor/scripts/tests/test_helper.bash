# shellcheck shell=bash
# test_helper.bash — common setup loaded by every *.bats file.

# Path conventions: this file lives in <plugin>/scripts/tests/.
TESTS_DIR="${BATS_TEST_DIRNAME}"
SCRIPTS_DIR="$(cd "$TESTS_DIR/.." && pwd)"
PLUGIN_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"
SHARED_DIR="$PLUGIN_DIR/shared"
FIXTURES_DIR="$TESTS_DIR/fixtures"

export TESTS_DIR SCRIPTS_DIR PLUGIN_DIR SHARED_DIR FIXTURES_DIR

# Tiny assertion helpers — keep dependencies to bats-core itself.

assert_eq() {
  # assert_eq <expected> <actual> [<message>]
  if [ "$1" != "$2" ]; then
    printf 'assert_eq failed: %s\n  expected: %q\n  actual:   %q\n' \
      "${3:-}" "$1" "$2" >&2
    return 1
  fi
}

assert_contains() {
  # assert_contains <haystack> <needle> [<message>]
  case "$1" in
    *"$2"*) return 0 ;;
    *)
      printf 'assert_contains failed: %s\n  haystack: %q\n  needle:   %q\n' \
        "${3:-}" "$1" "$2" >&2
      return 1
      ;;
  esac
}

# Build a fake linguist binary in $1 (a tempdir). The fake reads $FIXTURE_FILE
# and emits it on stdout, ignoring its CLI args. Returns the path so callers
# can prepend to PATH.
make_fake_linguist() {
  local target_dir="$1"
  local name="${2:-github-linguist}"
  local path="$target_dir/$name"
  cat > "$path" <<'EOF'
#!/usr/bin/env bash
# Fake linguist for tests: emits $FIXTURE_FILE content.
if [ -z "${FIXTURE_FILE:-}" ] || [ ! -f "$FIXTURE_FILE" ]; then
  echo "fake-linguist: FIXTURE_FILE not set or missing" >&2
  exit 1
fi
cat "$FIXTURE_FILE"
EOF
  chmod +x "$path"
  echo "$path"
}

# Skip the current test if a required tool is not on PATH. Use for tests that
# need real Java/PMD/Linguist.
require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    skip "required tool '$1' not on PATH"
  fi
}
