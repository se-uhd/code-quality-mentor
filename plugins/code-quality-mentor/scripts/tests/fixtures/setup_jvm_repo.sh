#!/usr/bin/env bash
# setup_jvm_repo.sh <target-dir>
#
# Materializes a tiny git repo with a Maven-shaped layout (src/main/java) and
# a single Java file that triggers known SpotBugs detectors. Used by
# run_spotbugs.bats and the SpotBugs branch of e2e_smoke.bats. Requires
# `javac` on PATH at *call time* if the caller wants compiled classes; this
# script only writes source. The caller is responsible for compilation.

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: setup_jvm_repo.sh <target-dir>" >&2
  exit 1
fi

target="$1"
mkdir -p "$target/src/main/java"
cd "$target"
git init -q -b main 2>/dev/null || git init -q
git config --local commit.gpgsign false
git config --local user.email "alice@example.com"
git config --local user.name  "Alice Example"

cat > src/main/java/Bug.java <<'EOF'
public class Bug {
    private int[] secret = new int[10];

    public int[] getSecret() {
        return secret;
    }

    public boolean equalStrings(String a, String b) {
        return a == b;
    }
}
EOF

git add src/main/java/Bug.java
GIT_AUTHOR_DATE="2026-04-01T10:00:00" GIT_COMMITTER_DATE="2026-04-01T10:00:00" \
  git commit -q -m "Add Bug"
