#!/usr/bin/env bash
# update_catalog.sh <subcommand> [args...]
#
# Maintain shared/antipatterns.json:
#   validate       — assert schema conformance and provenance integrity. Exits
#                    non-zero on the first failure, naming the offending id.
#   refresh-refs   — HEAD-check every URL in sources[] and entries[].canonical_references[].
#                    Read-only; reports non-2xx codes as "needs review".
#   diff-upstream  — compare entry names against shared/upstream_snapshots/*.json
#                    and report smells the upstream lists cover but we do not.
#                    Read-only; advisory.
#
# The interactive "add new entry" flow lives in the catalog skill
# (skills/catalog/SKILL.md) because LLM drafting requires the harness.

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
catalog="$script_dir/../shared/antipatterns.json"
schema="$script_dir/../shared/antipatterns.schema.json"
snapshots_dir="$script_dir/../shared/upstream_snapshots"

usage() {
  cat >&2 <<EOF
usage: update_catalog.sh <subcommand> [args]

subcommands:
  validate                    — schema + provenance checks (exits non-zero on failure)
  refresh-refs                — HEAD-check every URL; report non-2xx
  refresh-refs --offline      — skip the network and just count URLs to be checked
  diff-upstream               — list smells from snapshots not yet covered by entries[]
  --help, -h                  — this message

paths used:
  catalog:   $catalog
  schema:    $schema
  snapshots: $snapshots_dir
EOF
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "update_catalog: $1 is not on PATH" >&2
    exit 2
  }
}

# --- validate ------------------------------------------------------------

cmd_validate() {
  require_tool jq
  [ -f "$catalog" ] || { echo "update_catalog: missing catalog: $catalog" >&2; exit 1; }
  [ -f "$schema" ]  || { echo "update_catalog: missing schema: $schema"   >&2; exit 1; }

  # Optional formal validation via ajv if available; otherwise rely on the jq
  # checks below.
  if command -v ajv >/dev/null 2>&1; then
    if ! ajv validate -s "$schema" -d "$catalog" --strict=false >/dev/null 2>&1; then
      ajv validate -s "$schema" -d "$catalog" --strict=false >&2 || true
      echo "update_catalog: schema validation failed" >&2
      exit 1
    fi
  fi

  # Structural checks expressed as a single jq pipeline that builds a list of
  # error strings. If the list is non-empty we print them and exit non-zero;
  # otherwise we print one OK line. This works without ajv installed.
  errors=$(jq -r '
    def errs:
      [ if (.version // null) == null then "missing top-level .version" else empty end,
        if (.lastUpdated // null) == null then "missing top-level .lastUpdated" else empty end,
        if ((.sources | type) // "") != "array" then ".sources must be an array" else empty end,
        if ((.entries | type) // "") != "array" then ".entries must be an array" else empty end ]
      + ( if (.sources | type) == "array"
          then (
            ( if (.sources | map(.id) | length != (unique_by(.) | length))
                then ["duplicate source id(s) in .sources"] else [] end )
            + ( [ .sources[] |
                  ( if ((.id // "") == "") then "source has empty id" else empty end,
                    if ((.title // "") == "") then "source \(.id): missing title" else empty end,
                    if ((.url // "") == "") or ((.url // "") | startswith("http") | not)
                      then "source \(.id): missing or non-http url" else empty end ) ] )
          )
          else [] end )
      + ( (.sources // [] | map(.id)) as $src_ids
          | if (.entries | type) == "array"
            then (
              ( if (.entries | map(.id) | length != (unique_by(.) | length))
                  then ["duplicate entry id(s) in .entries"] else [] end )
              + [ .entries[] |
                  . as $e
                  | ( if (($e.id // "") == "") then "entry has empty id" else empty end,
                      if (($e.name // "") == "") then "entry \($e.id): missing name" else empty end,
                      if (($e.family // "") == "")
                        then "entry \($e.id): missing family"
                        elif ($e.family | IN("Bloaters","OO Abusers","Change Preventers","Dispensables","Couplers","Architecture") | not)
                        then "entry \($e.id): unknown family \"\($e.family)\""
                        else empty end,
                      if (($e.description // "") == "") then "entry \($e.id): missing description" else empty end,
                      if (($e.llm_detection_signals // []) | length) < 2
                        then "entry \($e.id): needs >= 2 llm_detection_signals" else empty end,
                      if (($e.refactoring // "") == "") then "entry \($e.id): missing refactoring" else empty end,
                      if (($e.seeded_from // []) | length) < 1
                        then "entry \($e.id): needs >= 1 seeded_from" else empty end,
                      ( ($e.seeded_from // [])[] as $sid
                        | if ($src_ids | index($sid)) == null
                          then "entry \($e.id): seeded_from \"\($sid)\" does not match any sources[].id"
                          else empty end ),
                      if (($e.canonical_references // []) | length) < 1
                        then "entry \($e.id): needs >= 1 canonical_reference" else empty end,
                      ( ($e.canonical_references // [])[] as $r
                        | ( if (($r.type // "") | IN("book","paper","talk","web","tool_docs") | not)
                            then "entry \($e.id): canonical_reference \"\(($r.title // ""))\": invalid type \"\($r.type // "")\""
                            else empty end,
                            if (($r.title // "") == "")
                            then "entry \($e.id): canonical_reference missing title"
                            else empty end,
                            if (($r.url // "") == "") or ((($r.url // "") | startswith("http")) | not)
                            then "entry \($e.id): canonical_reference \"\($r.title // "")\": missing or non-http url"
                            else empty end ) ),
                      if (($e.canonical_references // []) | map(select(.type != "tool_docs")) | length) < 1
                        then "entry \($e.id): only tool_docs references; need >= 1 book/paper/talk/web"
                        else empty end ) ]
            )
            else [] end );
    errs[]
  ' "$catalog")

  if [ -n "$errors" ]; then
    echo "$errors" >&2
    echo "" >&2
    echo "update_catalog: validation failed" >&2
    exit 1
  fi

  entry_count=$(jq '.entries | length' "$catalog")
  source_count=$(jq '.sources | length' "$catalog")
  echo "OK: $entry_count entries, $source_count sources"
}

# --- refresh-refs --------------------------------------------------------

cmd_refresh_refs() {
  local offline=0
  if [ "${1:-}" = "--offline" ]; then offline=1; fi
  require_tool jq
  [ -f "$catalog" ] || { echo "update_catalog: missing catalog: $catalog" >&2; exit 1; }

  # Emit one tsv row per URL: <where>\t<url>
  jq -r '
    [.sources[] | {where: ("source:" + .id), url: .url}]
    + [.entries[] as $e
       | $e.canonical_references[]
       | {where: ("entry:" + $e.id + ":" + (.title // "")), url: .url}]
    | .[]
    | [.where, .url] | @tsv
  ' "$catalog" > /tmp/cqm_urls.$$

  total=$(wc -l < /tmp/cqm_urls.$$ | tr -d ' ')
  if [ "$offline" -eq 1 ]; then
    echo "refresh-refs --offline: $total urls would be checked"
    rm -f /tmp/cqm_urls.$$
    return 0
  fi

  require_tool curl
  echo "refresh-refs: checking $total urls (HEAD, 10s timeout each)"
  bad=0
  while IFS=$'\t' read -r where url; do
    code=$(curl -sIL --max-time 10 -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo "000")
    case "$code" in
      2*|3*) status="ok" ;;
      *) status="NEEDS-REVIEW"; bad=$((bad + 1)) ;;
    esac
    printf '%s\t%s\t%s\t%s\n' "$status" "$code" "$where" "$url"
  done < /tmp/cqm_urls.$$
  rm -f /tmp/cqm_urls.$$
  echo "refresh-refs: done ($bad needing review)"
  # Read-only audit — never exit non-zero just because a URL is flaky.
  return 0
}

# --- diff-upstream -------------------------------------------------------

# Each upstream snapshot is a JSON array of strings (smell names). The
# snapshot files themselves are refreshed manually; this subcommand reports
# what is in the snapshot but not in our entries[].name set.
cmd_diff_upstream() {
  require_tool jq
  [ -f "$catalog" ] || { echo "update_catalog: missing catalog: $catalog" >&2; exit 1; }
  if [ ! -d "$snapshots_dir" ]; then
    echo "diff-upstream: no snapshots dir at $snapshots_dir (nothing to compare)"
    return 0
  fi

  shopt -s nullglob
  files=("$snapshots_dir"/*.json)
  if [ "${#files[@]}" -eq 0 ]; then
    echo "diff-upstream: no *.json snapshots in $snapshots_dir"
    return 0
  fi

  # Fuzzy match: compare lowercased names with non-alphanumeric stripped.
  for snap in "${files[@]}"; do
    name=$(basename "$snap" .json)
    missing=$(jq -r --slurpfile cat "$catalog" '
      def norm: ascii_downcase | gsub("[^a-z0-9]"; "");
      (($cat[0].entries | map(.name | norm)) | unique) as $ours |
      . | map({original: ., key: norm}) | unique_by(.key)
        | map(select(.key as $k | $ours | index($k) | not))
        | map(.original)
    ' "$snap")
    count=$(echo "$missing" | jq 'length')
    echo "----"
    echo "snapshot: $name ($count smells not yet covered)"
    if [ "$count" -gt 0 ]; then
      jq -r '.[]' <<< "$missing"
    fi
  done
}

# --- dispatch ------------------------------------------------------------

case "${1:-}" in
  validate)        shift; cmd_validate "$@" ;;
  refresh-refs)    shift; cmd_refresh_refs "$@" ;;
  diff-upstream)   shift; cmd_diff_upstream "$@" ;;
  -h|--help|help|"") usage; exit 0 ;;
  *) echo "update_catalog: unknown subcommand: $1" >&2; usage; exit 2 ;;
esac
