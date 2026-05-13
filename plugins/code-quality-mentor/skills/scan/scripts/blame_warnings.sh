#!/usr/bin/env bash
# blame_warnings.sh <repo-root> [findings-report.json]
#
# Read a PMD-shape JSON report — produced by PMD, the LLM antipattern scan,
# or the merger of both (default: <repo-root>/.code-quality-mentor/pmd-report.json), attribute
# each warning's `beginline` to a git-blame author, then aggregate per author.
# Writes the result to
#   <repo-root>/.code-quality-mentor/blame-report.json
# and prints that path on stdout.
#
# The output JSON is an array, sorted by warning_count descending:
#   [
#     {
#       "author_email": "alice@example.com",
#       "author_name":  "Alice Example",
#       "warning_count": 17,
#       "warnings": [
#         {"file": "/abs/Foo.java", "line": 42, "rule": "EmptyCatchBlock",
#          "message": "..."},
#         ...
#       ]
#     },
#     ...
#   ]
#
# Implementation notes:
#  - One `git blame --porcelain` invocation per file (not per warning) keeps
#    process spawn cost bounded on large reports.
#  - Attribution uses each warning's `beginline`. A warning spanning multiple
#    lines is still attributed to a single author — the author of its first
#    line. This matches how readers naturally locate violations.
#  - Author identity is keyed by email, which is more stable than display name
#    across `git config user.name` drift.

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: blame_warnings.sh <repo-root> [pmd-report.json]" >&2
  exit 1
fi

repo_root="$1"
pmd_report="${2:-$repo_root/.code-quality-mentor/pmd-report.json}"

if [ ! -d "$repo_root" ]; then
  echo "blame_warnings: not a directory: $repo_root" >&2
  exit 1
fi
if [ ! -f "$pmd_report" ]; then
  echo "blame_warnings: findings report not found: $pmd_report" >&2
  exit 1
fi
for tool in jq awk git; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "blame_warnings: $tool is not on PATH" >&2
    exit 1
  fi
done

out_dir="$repo_root/.code-quality-mentor"
mkdir -p "$out_dir"
out_report="$out_dir/blame-report.json"

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

warnings_tsv="$work_dir/warnings.tsv"
files_list="$work_dir/files.txt"
blame_tsv="$work_dir/blame.tsv"
blame_index="$work_dir/blame-index.json"

# --- 1. Flatten warnings to TSV ----------------------------------------
jq -r '
  .files[]? as $f
  | $f.violations[]?
  | [$f.filename, .beginline, .endline, .rule, (.description // "")]
  | @tsv
' "$pmd_report" > "$warnings_tsv"

if [ ! -s "$warnings_tsv" ]; then
  # No warnings at all — write an empty author list and exit.
  echo '[]' > "$out_report"
  echo "$out_report"
  exit 0
fi

awk -F'\t' '{print $1}' "$warnings_tsv" | sort -u > "$files_list"

# --- 2. For each file, run git blame once and emit per-line authorship -
: > "$blame_tsv"
while IFS= read -r pmd_path; do
  [ -z "$pmd_path" ] && continue

  # PMD typically emits absolute paths. If we got a relative one, anchor it.
  if [ "${pmd_path:0:1}" = "/" ]; then
    abs_file="$pmd_path"
  else
    abs_file="$repo_root/$pmd_path"
  fi

  if [ ! -f "$abs_file" ]; then
    # File was deleted in HEAD; we cannot blame it. Skip.
    continue
  fi

  # git -C lets us pass an absolute path even when CWD is elsewhere.
  if ! git -C "$repo_root" blame --porcelain -- "$abs_file" 2>/dev/null \
       | awk -v file="$pmd_path" '
           /^[0-9a-f]{40} / { split($0,a," "); sha=a[1]; line=a[3]; next }
           /^author /       { if (!(sha in name)) { name[sha]=substr($0,8) } ; next }
           /^author-mail /  { if (!(sha in mail)) {
                                m=substr($0,14); sub(/^</,"",m); sub(/>$/,"",m);
                                mail[sha]=m
                              } ; next }
           /^\t/            { print file "\t" line "\t" mail[sha] "\t" name[sha] }
         ' >> "$blame_tsv"; then
    # Blame failed (e.g., file untracked); skip silently.
    continue
  fi
done < "$files_list"

# --- 3. Build a lookup index keyed by "<file>\t<line>" -----------------
jq -Rn '
  [inputs
   | select(length > 0)
   | split("\t")
   | select(length >= 4)
   | {key: (.[0] + "\t" + .[1]), value: {email: .[2], name: .[3]}}]
  | from_entries
' < "$blame_tsv" > "$blame_index"

# --- 4. Join warnings with blame index, aggregate by author email ------
jq --slurpfile bi "$blame_index" '
  [
    .files[]? as $f
    | $f.violations[]?
    | . as $v
    | ($bi[0][$f.filename + "\t" + ($v.beginline|tostring)] // null) as $b
    | select($b != null)
    | {
        file:    $f.filename,
        line:    $v.beginline,
        rule:    $v.rule,
        message: ($v.description // "")
      } + $b
  ]
  | group_by(.email)
  | map({
      author_email:  .[0].email,
      author_name:   .[0].name,
      warning_count: length,
      warnings:      map({file, line, rule, message})
    })
  | sort_by(-.warning_count)
' "$pmd_report" > "$out_report"

echo "$out_report"
