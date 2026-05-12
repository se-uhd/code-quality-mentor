#!/usr/bin/env bash
# setup_tiny_java_repo.sh <target-dir>
#
# Materializes a small synthetic git repository at <target-dir> with two
# committers and three Java files, each seeded with a known PMD violation.
# Used by e2e_smoke.bats; works on a fresh tempdir.

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: setup_tiny_java_repo.sh <target-dir>" >&2
  exit 1
fi

target="$1"
mkdir -p "$target/src"
cd "$target"

# Start with a clean, isolated git config — do not inherit user identity.
git init -q -b main 2>/dev/null || git init -q
git config --local commit.gpgsign false
git config --local tag.gpgsign false
git config --local user.email "alice@example.com"
git config --local user.name  "Alice Example"

# --- Alice commits Foo.java (UnusedLocalVariable + EmptyCatchBlock) ----
cat > src/Foo.java <<'EOF'
public class Foo {
    public void doThing() {
        int unused = 42;
        try {
            Thread.sleep(1);
        } catch (InterruptedException e) {
        }
    }
}
EOF
git add src/Foo.java
GIT_AUTHOR_DATE="2026-04-01T10:00:00" GIT_COMMITTER_DATE="2026-04-01T10:00:00" \
  git commit -q -m "Add Foo"

# --- Bob commits Bar.java (AvoidPrintStackTrace) -----------------------
git config --local user.email "bob@example.com"
git config --local user.name  "Bob Builder"
cat > src/Bar.java <<'EOF'
public class Bar {
    public void doThing() {
        try {
            riskyOp();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
    private void riskyOp() throws Exception {}
}
EOF
git add src/Bar.java
GIT_AUTHOR_DATE="2026-04-02T10:00:00" GIT_COMMITTER_DATE="2026-04-02T10:00:00" \
  git commit -q -m "Add Bar"

# --- Bob commits Baz.java (EmptyCatchBlock) ----------------------------
cat > src/Baz.java <<'EOF'
public class Baz {
    public void doThing() {
        try {
            Thread.sleep(1);
        } catch (InterruptedException e) {
        }
    }
}
EOF
git add src/Baz.java
GIT_AUTHOR_DATE="2026-04-03T10:00:00" GIT_COMMITTER_DATE="2026-04-03T10:00:00" \
  git commit -q -m "Add Baz"
