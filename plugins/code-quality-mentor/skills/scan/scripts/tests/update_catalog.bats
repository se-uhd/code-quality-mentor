#!/usr/bin/env bats

load 'test_helper'

setup() {
  require_tool jq

  # Pin the catalog and schema under test by overriding the script's paths.
  # We create a temp skill layout (scripts/ + assets/) that mirrors the real
  # one so the script's relative path math works unchanged.
  WORK="$BATS_TEST_TMPDIR/work"
  mkdir -p "$WORK/skill/scripts" "$WORK/skill/assets"
  cp "$SCRIPTS_DIR/update_catalog.sh" "$WORK/skill/scripts/update_catalog.sh"
  chmod +x "$WORK/skill/scripts/update_catalog.sh"
  cp "$ASSETS_DIR/antipatterns.schema.json" "$WORK/skill/assets/antipatterns.schema.json"

  CAT="$WORK/skill/assets/antipatterns.json"
  SCRIPT="$WORK/skill/scripts/update_catalog.sh"

  # Minimal valid catalog: one source, one entry.
  cat > "$CAT" <<'EOF'
{
  "version": "0.0.1",
  "lastUpdated": "2026-05-13",
  "sources": [
    {
      "id": "fowler_refactoring",
      "title": "Refactoring (2nd ed.)",
      "url": "https://martinfowler.com/books/refactoring.html"
    }
  ],
  "entries": [
    {
      "id": "long_method",
      "name": "Long Method",
      "family": "Bloaters",
      "description": "A method that is too long.",
      "llm_detection_signals": ["body > 30 lines", "internal section comments"],
      "refactoring": "Extract Method.",
      "seeded_from": ["fowler_refactoring"],
      "canonical_references": [
        {
          "type": "book",
          "title": "Refactoring (2nd ed.)",
          "url": "https://martinfowler.com/books/refactoring.html"
        }
      ]
    }
  ]
}
EOF
}

@test "validate: passes on a minimal valid catalog" {
  run "$SCRIPT" validate
  assert_eq 0 "$status" "exit code"
  assert_contains "$output" "OK:"
  assert_contains "$output" "1 entries"
  assert_contains "$output" "1 sources"
}

@test "validate: passes on the bundled seed catalog" {
  # Sanity check against the real catalog so the seed never regresses.
  run "$SCRIPTS_DIR/update_catalog.sh" validate
  assert_eq 0 "$status" "exit code"
  assert_contains "$output" "OK:"
}

@test "validate: fails when an entry has no canonical_references" {
  jq '.entries[0].canonical_references = []' "$CAT" > "$CAT.tmp" && mv "$CAT.tmp" "$CAT"
  run "$SCRIPT" validate
  assert_eq 1 "$status" "exit code"
  assert_contains "$output" "long_method"
  assert_contains "$output" "canonical_reference"
}

@test "validate: fails when a canonical_reference has no url" {
  jq 'del(.entries[0].canonical_references[0].url)' "$CAT" > "$CAT.tmp" && mv "$CAT.tmp" "$CAT"
  run "$SCRIPT" validate
  assert_eq 1 "$status" "exit code"
  assert_contains "$output" "missing or non-http url"
}

@test "validate: fails when a canonical_reference url is not http(s)" {
  jq '.entries[0].canonical_references[0].url = "not-a-url"' "$CAT" > "$CAT.tmp" && mv "$CAT.tmp" "$CAT"
  run "$SCRIPT" validate
  assert_eq 1 "$status" "exit code"
  assert_contains "$output" "missing or non-http url"
}

@test "validate: fails when a source has no url" {
  jq 'del(.sources[0].url)' "$CAT" > "$CAT.tmp" && mv "$CAT.tmp" "$CAT"
  run "$SCRIPT" validate
  assert_eq 1 "$status" "exit code"
  assert_contains "$output" "missing or non-http url"
}

@test "validate: fails when seeded_from references an unknown source" {
  jq '.entries[0].seeded_from = ["does_not_exist"]' "$CAT" > "$CAT.tmp" && mv "$CAT.tmp" "$CAT"
  run "$SCRIPT" validate
  assert_eq 1 "$status" "exit code"
  assert_contains "$output" "does_not_exist"
  assert_contains "$output" "does not match any sources"
}

@test "validate: fails on duplicate entry ids" {
  jq '.entries += [.entries[0]]' "$CAT" > "$CAT.tmp" && mv "$CAT.tmp" "$CAT"
  run "$SCRIPT" validate
  assert_eq 1 "$status" "exit code"
  assert_contains "$output" "duplicate entry id"
}

@test "validate: fails on unknown family" {
  jq '.entries[0].family = "Not A Family"' "$CAT" > "$CAT.tmp" && mv "$CAT.tmp" "$CAT"
  run "$SCRIPT" validate
  assert_eq 1 "$status" "exit code"
  assert_contains "$output" "unknown family"
}

@test "validate: fails when llm_detection_signals has fewer than 2 entries" {
  jq '.entries[0].llm_detection_signals = ["only one"]' "$CAT" > "$CAT.tmp" && mv "$CAT.tmp" "$CAT"
  run "$SCRIPT" validate
  assert_eq 1 "$status" "exit code"
  assert_contains "$output" "needs >= 2 llm_detection_signals"
}

@test "validate: fails when an entry has only tool_docs references" {
  jq '.entries[0].canonical_references[0].type = "tool_docs"' "$CAT" > "$CAT.tmp" && mv "$CAT.tmp" "$CAT"
  run "$SCRIPT" validate
  assert_eq 1 "$status" "exit code"
  assert_contains "$output" "only tool_docs references"
}

@test "refresh-refs --offline: counts urls without network" {
  run "$SCRIPT" refresh-refs --offline
  assert_eq 0 "$status" "exit code"
  assert_contains "$output" "2 urls would be checked"
}

@test "diff-upstream: reports smells the catalog does not yet cover" {
  mkdir -p "$WORK/skill/assets/upstream_snapshots"
  cat > "$WORK/skill/assets/upstream_snapshots/test_source.json" <<'EOF'
["Long Method", "God Class", "Lava Flow"]
EOF
  run "$SCRIPT" diff-upstream
  assert_eq 0 "$status" "exit code"
  assert_contains "$output" "test_source"
  assert_contains "$output" "God Class"
  assert_contains "$output" "Lava Flow"
  # Long Method is already in the test catalog -> should NOT be in the missing list.
  case "$output" in
    *"missing"*"Long Method"*) echo "Long Method incorrectly listed" >&2; return 1 ;;
  esac
}

@test "diff-upstream: graceful when no snapshots dir exists" {
  run "$SCRIPT" diff-upstream
  assert_eq 0 "$status" "exit code"
  assert_contains "$output" "no snapshots dir"
}

@test "unknown subcommand: prints usage and exits 2" {
  run "$SCRIPT" not-a-subcommand
  assert_eq 2 "$status" "exit code"
  assert_contains "$output" "unknown subcommand"
}

@test "--help: prints usage and exits 0" {
  run "$SCRIPT" --help
  assert_eq 0 "$status" "exit code"
  assert_contains "$output" "subcommands:"
}
