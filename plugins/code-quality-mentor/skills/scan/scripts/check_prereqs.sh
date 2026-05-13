#!/usr/bin/env bash
# check_prereqs.sh
#
# Verify that every external tool the plugin needs is on PATH. Print one-line
# install hints for anything missing. Exit 0 if all required tools are present,
# 1 otherwise.
#
# Required: pmd (>=7), jq, git, and one of {github-linguist, enry}.
# Java (>=11) is required transitively as PMD's runtime.

set -euo pipefail

missing=0

note_missing() {
  # $1: tool name, $2: one-line install hint
  printf 'missing: %s\n  install: %s\n' "$1" "$2" >&2
  missing=1
}

# --- java (PMD runtime) --------------------------------------------------
if ! command -v java >/dev/null 2>&1; then
  note_missing "java (>=11, required by PMD 7)" \
    "macOS: 'brew install temurin' or via SDKMAN. Linux: use the distro package or download a JDK from adoptium.net."
else
  # Best-effort version parse; PMD 7 requires Java 11+.
  if java_version=$(java -version 2>&1 | head -1 | awk -F'"' '{print $2}'); then
    major=$(printf '%s' "$java_version" | awk -F. '{print ($1 == 1 ? $2 : $1)}')
    if [ -n "$major" ] && [ "$major" -lt 11 ] 2>/dev/null; then
      printf 'warning: java %s detected; PMD 7 requires Java 11+\n' "$java_version" >&2
    fi
  fi
fi

# --- pmd -----------------------------------------------------------------
if ! command -v pmd >/dev/null 2>&1; then
  note_missing "pmd (>=7)" \
    "macOS: 'brew install pmd'. Other platforms: download from https://github.com/pmd/pmd/releases and add bin/ to PATH."
fi

# --- jq ------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  note_missing "jq" \
    "macOS: 'brew install jq'. Debian/Ubuntu: 'apt-get install jq'. Other: https://jqlang.github.io/jq/download/"
fi

# --- git -----------------------------------------------------------------
if ! command -v git >/dev/null 2>&1; then
  note_missing "git" \
    "macOS: 'xcode-select --install' or 'brew install git'. Linux: distro package."
fi

# --- linguist or enry ----------------------------------------------------
if ! command -v github-linguist >/dev/null 2>&1 && ! command -v enry >/dev/null 2>&1; then
  note_missing "github-linguist OR enry" \
    "Prefer 'gem install github-linguist' (needs Ruby + libicu). Alternative: 'brew install enry' (single Go binary, no Ruby)."
fi

if [ "$missing" -ne 0 ]; then
  echo "" >&2
  echo "check_prereqs: one or more required tools are missing. See hints above." >&2
  exit 1
fi
