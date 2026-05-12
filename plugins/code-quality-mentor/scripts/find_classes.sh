#!/usr/bin/env bash
# find_classes.sh <repo-root>
#
# Locate compiled JVM bytecode directories (and JARs) inside a Git repository
# so the SpotBugs analyzer has something to chew on. Probes the canonical
# build-output paths produced by Maven, Gradle, IntelliJ, and Eclipse.
#
# Output on stdout: a JSON object with two arrays — `class_dirs` (compiled
# bytecode directories) and `source_dirs` (matching source roots). Both lists
# are deduplicated and contain only paths that actually exist.
#
# Exit codes:
#   0 + JSON on stdout: probe succeeded (output may have empty arrays when
#       nothing was built yet — that is a normal state, not an error).
#   1 + message on stderr: invalid input.

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: find_classes.sh <repo-root>" >&2
  exit 1
fi

repo_root="$1"
if [ ! -d "$repo_root" ]; then
  echo "find_classes: not a directory: $repo_root" >&2
  exit 1
fi

class_candidates=(
  "target/classes"
  "target/test-classes"
  "build/classes/java/main"
  "build/classes/java/test"
  "build/classes/kotlin/main"
  "build/classes/kotlin/test"
  "out/production/classes"
  "bin/main"
  "bin"
)

source_candidates=(
  "src/main/java"
  "src/main/kotlin"
  "src/test/java"
  "src/test/kotlin"
  "src/java"
  "src/kotlin"
  "src"
)

found_class=()
for rel in "${class_candidates[@]}"; do
  if [ -d "$repo_root/$rel" ]; then
    # Only count it if there is at least one .class file underneath.
    if find "$repo_root/$rel" -name '*.class' -print -quit | grep -q '.'; then
      found_class+=("$repo_root/$rel")
    fi
  fi
done

# Also pick up build JARs and module JARs (Gradle defaults).
for jar_dir in "$repo_root/target" "$repo_root/build/libs"; do
  if [ -d "$jar_dir" ]; then
    for jar in "$jar_dir"/*.jar; do
      [ -f "$jar" ] && found_class+=("$jar")
    done
  fi
done

found_source=()
for rel in "${source_candidates[@]}"; do
  if [ -d "$repo_root/$rel" ]; then
    found_source+=("$repo_root/$rel")
  fi
done
# Always include the repo root itself so unpackaged source files resolve too.
found_source+=("$repo_root")

# Emit JSON via jq (handles quoting safely). The `select(length > 0)` guards
# against bash 3.2's `printf '%s\n' "${empty_array[@]}"` emitting a single
# blank line, which would otherwise become a `[""]` entry.
class_json=$(printf '%s\n' "${found_class[@]+"${found_class[@]}"}" \
  | jq -R . | jq -s '[.[] | select(length > 0)] | unique')
source_json=$(printf '%s\n' "${found_source[@]+"${found_source[@]}"}" \
  | jq -R . | jq -s '[.[] | select(length > 0)] | unique')

jq -n --argjson c "$class_json" --argjson s "$source_json" \
  '{class_dirs: $c, source_dirs: $s}'
