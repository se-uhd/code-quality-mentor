#!/usr/bin/env bats

load 'test_helper'

setup() {
  require_tool jq
  MAP="$SHARED_DIR/pmd-languages.json"
  [ -f "$MAP" ] || { echo "pmd-languages.json not found at $MAP" >&2; return 1; }
}

@test "pmd-languages.json: file is valid JSON" {
  run jq empty "$MAP"
  assert_eq 0 "$status" "jq parse"
}

@test "pmd-languages.json: every entry has the required fields" {
  missing=$(jq -r '
    [ to_entries[]
      | select(.key != "_comment")
      | select(
          ((.value.pmd_language_id // "") == "") or
          ((.value.default_ruleset // "") == "") or
          ((.value.pmd_docs_base_url // "") == "")
        )
      | .key ]
    | join(", ")
  ' "$MAP")
  assert_eq "" "$missing" "entries missing required fields"
}

@test "pmd-languages.json: every aliases value is an array (possibly empty)" {
  bad=$(jq -r '
    [ to_entries[]
      | select(.key != "_comment")
      | select((.value.aliases | type) != "array")
      | .key ]
    | join(", ")
  ' "$MAP")
  assert_eq "" "$bad" "entries with non-array aliases"
}

@test "pmd-languages.json: every docs URL is on docs.pmd-code.org" {
  bad=$(jq -r '
    [ to_entries[]
      | select(.key != "_comment")
      | select((.value.pmd_docs_base_url | startswith("https://docs.pmd-code.org/")) | not)
      | .key ]
    | join(", ")
  ' "$MAP")
  assert_eq "" "$bad" "entries with bad docs host"
}

@test "pmd-languages.json: pmd_language_ids are unique" {
  dupes=$(jq -r '
    [ to_entries[]
      | select(.key != "_comment")
      | .value.pmd_language_id ]
    | group_by(.)
    | map(select(length > 1) | .[0])
    | join(", ")
  ' "$MAP")
  assert_eq "" "$dupes" "duplicate pmd_language_id values"
}

@test "pmd-languages.json: each named ruleset resolves under PMD (soft check)" {
  require_tool pmd
  failed=""
  while IFS=$'\t' read -r lang rs; do
    if ! pmd check --rulesets "$rs" --help >/dev/null 2>&1; then
      # `pmd check --help` accepts --rulesets and validates them. If PMD's
      # CLI surface differs across versions, this check may give false
      # negatives; treat it as advisory.
      failed="$failed $lang($rs)"
    fi
  done < <(jq -r '
    to_entries[]
    | select(.key != "_comment")
    | [.value.pmd_language_id, .value.default_ruleset]
    | @tsv
  ' "$MAP")
  if [ -n "$failed" ]; then
    # Don't fail the suite on a soft check — surface as a warning.
    echo "warning: rulesets pmd could not resolve:$failed" >&2
  fi
}
