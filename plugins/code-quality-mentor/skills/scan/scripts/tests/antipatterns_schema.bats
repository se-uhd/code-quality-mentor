#!/usr/bin/env bats

load 'test_helper'

setup() {
  require_tool jq
}

@test "antipatterns.json: parses as valid JSON" {
  run jq -e 'type == "object"' "$ASSETS_DIR/antipatterns.json"
  assert_eq 0 "$status" "exit code"
}

@test "antipatterns.schema.json: parses as valid JSON" {
  run jq -e '."$schema" != null' "$ASSETS_DIR/antipatterns.schema.json"
  assert_eq 0 "$status" "exit code"
}

@test "antipatterns.json: top-level structure has version, lastUpdated, sources, entries" {
  result=$(jq -r '
    [(.version | type), (.lastUpdated | type), (.sources | type), (.entries | type)] | join(",")
  ' "$ASSETS_DIR/antipatterns.json")
  assert_eq "string,string,array,array" "$result" "top-level types"
}

@test "antipatterns.json: every entry id is snake_case and unique" {
  bad=$(jq -r '[.entries[].id | select(test("^[a-z][a-z0-9_]*$") | not)] | join(",")' "$ASSETS_DIR/antipatterns.json")
  assert_eq "" "$bad" "non-snake_case ids"

  dup_count=$(jq '([.entries[].id] | length) - ([.entries[].id] | unique | length)' "$ASSETS_DIR/antipatterns.json")
  assert_eq 0 "$dup_count" "duplicate entry ids"
}

@test "antipatterns.json: every seeded_from id resolves to a known source" {
  unresolved=$(jq -r '
    (.sources | map(.id)) as $src |
    [.entries[] | .id as $eid | .seeded_from[] | select(. as $s | $src | index($s) | not) | "\($eid):\(.)"]
    | join(",")
  ' "$ASSETS_DIR/antipatterns.json")
  assert_eq "" "$unresolved" "unresolved seeded_from references"
}

@test "antipatterns.json: every source has a non-empty url starting with http" {
  bad=$(jq -r '[.sources[] | select((.url | startswith("http")) | not) | .id] | join(",")' "$ASSETS_DIR/antipatterns.json")
  assert_eq "" "$bad" "sources missing http url"
}

@test "antipatterns.json: every canonical_reference has a url starting with http" {
  bad=$(jq -r '
    [.entries[] | .id as $eid | .canonical_references[]
     | select((.url // "" | startswith("http")) | not)
     | "\($eid):\(.title // "<no title>")"]
    | join(",")
  ' "$ASSETS_DIR/antipatterns.json")
  assert_eq "" "$bad" "canonical_references missing http url"
}

@test "antipatterns.json: every entry has at least one non-tool_docs reference" {
  bad=$(jq -r '
    [.entries[] | select((.canonical_references | map(select(.type != "tool_docs")) | length) < 1) | .id]
    | join(",")
  ' "$ASSETS_DIR/antipatterns.json")
  assert_eq "" "$bad" "entries with only tool_docs references"
}

@test "antipatterns.json: every family is one of the schema enum values" {
  bad=$(jq -r '
    [.entries[] | select(.family | IN("Bloaters","OO Abusers","Change Preventers","Dispensables","Couplers","Architecture") | not) | "\(.id):\(.family)"]
    | join(",")
  ' "$ASSETS_DIR/antipatterns.json")
  assert_eq "" "$bad" "entries with unknown family"
}
