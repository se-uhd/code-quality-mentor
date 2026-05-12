#!/usr/bin/env bash
# spotbugs_xml_to_pmd.sh <spotbugs.xml> <source-dir> [<source-dir>...]
#
# Convert a SpotBugs XML report (produced with `-xml:withMessages`) into the
# PMD-shape JSON used elsewhere in this plugin. Source paths embedded in the
# SpotBugs XML are resolved to absolute paths by searching each `<source-dir>`
# argument in turn for the relative file; bugs whose source file cannot be
# found are dropped.
#
# Writes JSON to stdout. Requires `jq` and `awk` on PATH.

set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: spotbugs_xml_to_pmd.sh <spotbugs.xml> <source-dir> [<source-dir>...]" >&2
  exit 1
fi

xml="$1"
shift
source_dirs=("$@")

if [ ! -f "$xml" ]; then
  echo "spotbugs_xml_to_pmd: not a file: $xml" >&2
  exit 1
fi
for t in jq awk; do
  command -v "$t" >/dev/null 2>&1 || { echo "spotbugs_xml_to_pmd: $t not on PATH" >&2; exit 1; }
done

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

extracted="$work_dir/bugs.tsv"
resolved="$work_dir/resolved.tsv"

# Step 1: awk over the XML to emit one TSV row per BugInstance.
awk '
  function attr(line, name,    pat, off, val) {
    pat = name "=\""
    if (match(line, pat)) {
      off = RSTART + length(pat) - 1
      val = substr(line, off + 1)
      sub(/".*/, "", val)
      return val
    }
    return ""
  }
  /<BugInstance / {
    type_v     = attr($0, "type")
    cat_v      = attr($0, "category")
    pri_v      = attr($0, "priority")
    long_msg   = ""
    src_v      = ""; start_v = ""; end_v = ""
    in_bug     = 1
    seen_msg   = 0
    next
  }
  in_bug && /<LongMessage>/ && !seen_msg {
    line = $0
    sub(/.*<LongMessage>/, "", line)
    sub(/<\/LongMessage>.*/, "", line)
    long_msg = line
    seen_msg = 1
    next
  }
  in_bug && /<SourceLine[^>]*primary="true"/ {
    src_v   = attr($0, "sourcepath")
    start_v = attr($0, "start")
    end_v   = attr($0, "end")
    next
  }
  /<\/BugInstance>/ {
    if (in_bug && src_v != "" && start_v != "") {
      gsub(/\t/, " ", long_msg)
      print src_v "\t" start_v "\t" end_v "\t" type_v "\t" cat_v "\t" pri_v "\t" long_msg
    }
    in_bug = 0
  }
' "$xml" > "$extracted"

# Step 2: for each unique source-relative path, pick the first source dir
# where the file actually exists. Drop entries that cannot be resolved.
: > "$resolved"
awk -F'\t' '{print $1}' "$extracted" | sort -u | while IFS= read -r rel; do
  [ -z "$rel" ] && continue
  abs=""
  for root in "${source_dirs[@]}"; do
    if [ -f "$root/$rel" ]; then abs="$root/$rel"; break; fi
  done
  printf '%s\t%s\n' "$rel" "$abs" >> "$resolved"
done

# Step 3: join in jq and emit PMD-shape JSON.
jq -Rn \
  --rawfile bugs "$extracted" \
  --rawfile resolved "$resolved" \
  '
    ($resolved
      | split("\n")
      | map(select(length > 0))
      | map(split("\t"))
      | map(select(length == 2))
      | map({key: .[0], value: .[1]})
      | from_entries) as $lookup
    | ($bugs
      | split("\n")
      | map(select(length > 0))
      | map(split("\t"))
      | map(select(length >= 7))
      | map({
          src_rel:     .[0],
          beginline:   (.[1] | tonumber),
          endline:     (.[2] | tonumber? // (.[1] | tonumber)),
          rule:        .[3],
          ruleset:     .[4],
          priority:    (.[5] | tonumber? // 3),
          description: .[6]
        })
      | map(. + {filename: ($lookup[.src_rel] // "")})
      | map(select(.filename != ""))
      | group_by(.filename)
      | map({
          filename: .[0].filename,
          violations: map({beginline, endline, rule, ruleset, description, priority})
        }))
    | {formatVersion: 0, pmdVersion: "spotbugs", files: .}
  '
