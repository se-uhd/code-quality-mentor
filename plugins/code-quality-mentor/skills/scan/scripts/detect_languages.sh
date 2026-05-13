#!/usr/bin/env bash
# detect_languages.sh <repo-root>
#
# Detect the programming languages present in a Git repository using
# GitHub Linguist (preferred) or enry (fallback), then intersect with the
# languages PMD supports (per assets/pmd-languages.json).
#
# Output on stdout: a JSON array of objects, one per matched language:
#   [
#     {
#       "language": "Java",
#       "pmd_language_id": "java",
#       "ruleset": "category/java/quickstart.xml",
#       "pmd_docs_base_url": "https://docs.pmd-code.org/latest/pmd_rules_java.html",
#       "metric": 42
#     },
#     ...
#   ]
#
# `metric` is file count when produced by enry, byte size when produced by
# github-linguist. It is used only for ordering, never as a hard threshold.
#
# Environment overrides (test hooks):
#   LINGUIST_BIN  — path to the linguist binary to use (default: auto-detect)
#   PMD_LANG_MAP  — path to pmd-languages.json (default: ../assets/pmd-languages.json)
#
# Exit codes:
#   0 + JSON on stdout: detection succeeded (output may be `[]` if no PMD
#       language is present in the repo).
#   1 + message on stderr: invalid input, missing tools, or detection failed.

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: detect_languages.sh <repo-root>" >&2
  exit 1
fi

repo_root="$1"
if [ ! -d "$repo_root" ]; then
  echo "detect_languages: not a directory: $repo_root" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
pmd_lang_map="${PMD_LANG_MAP:-$script_dir/../assets/pmd-languages.json}"

if [ ! -f "$pmd_lang_map" ]; then
  echo "detect_languages: pmd-languages.json not found: $pmd_lang_map" >&2
  exit 1
fi

# --- pick a linguist implementation -------------------------------------
linguist_bin="${LINGUIST_BIN:-}"
linguist_kind=""

if [ -n "$linguist_bin" ]; then
  case "$(basename "$linguist_bin")" in
    *github-linguist*|*linguist*) linguist_kind="linguist" ;;
    *enry*) linguist_kind="enry" ;;
    *)
      # Fall back to format heuristics later; tag as unknown for now.
      linguist_kind="unknown"
      ;;
  esac
elif command -v github-linguist >/dev/null 2>&1; then
  linguist_bin="github-linguist"
  linguist_kind="linguist"
elif command -v enry >/dev/null 2>&1; then
  linguist_bin="enry"
  linguist_kind="enry"
else
  echo "detect_languages: neither github-linguist nor enry is on PATH" >&2
  exit 1
fi

# --- run the linguist tool ----------------------------------------------
raw_json=""
if [ "$linguist_kind" = "linguist" ]; then
  # github-linguist --json: object keyed by language with {size, percentage, ...}
  raw_json=$("$linguist_bin" --json "$repo_root" 2>/dev/null) || {
    echo "detect_languages: github-linguist failed on $repo_root" >&2
    exit 1
  }
elif [ "$linguist_kind" = "enry" ]; then
  # enry --json: object keyed by language with array of file paths
  raw_json=$("$linguist_bin" -json "$repo_root" 2>/dev/null) || \
  raw_json=$("$linguist_bin" --json "$repo_root" 2>/dev/null) || {
    echo "detect_languages: enry failed on $repo_root" >&2
    exit 1
  }
else
  # Unknown binary — try `--json` and trust the JSON shape detection in jq.
  raw_json=$("$linguist_bin" --json "$repo_root" 2>/dev/null) || {
    echo "detect_languages: $linguist_bin --json failed on $repo_root" >&2
    exit 1
  }
fi

# Empty repo: emit empty array and exit successfully.
if [ -z "$raw_json" ] || [ "$raw_json" = "null" ]; then
  echo "[]"
  exit 0
fi

# --- join with pmd-languages.json via jq -------------------------------
# For each entry in pmd-languages.json (skipping the _comment key), look up
# both the canonical Linguist name and any aliases in the linguist output.
# Emit a matched record using whichever name resolved first.

echo "$raw_json" | jq --slurpfile pmd "$pmd_lang_map" '
  . as $ling
  | $pmd[0]
  | to_entries
  | map(select(.key != "_comment"))
  | map(
      . as $entry
      | ([$entry.key] + ($entry.value.aliases // []))
      | map(select(. as $n | $ling | has($n)))
      | first as $matched
      | if $matched != null then
          {
            language: $matched,
            pmd_language_id: $entry.value.pmd_language_id,
            ruleset: $entry.value.default_ruleset,
            pmd_docs_base_url: $entry.value.pmd_docs_base_url,
            metric: (
              $ling[$matched]
              | if type == "array" then length
                elif type == "object" then (.size // .files // 0)
                elif type == "number" then .
                else 0 end
            )
          }
        else empty end
    )
  | sort_by(-.metric)
'
