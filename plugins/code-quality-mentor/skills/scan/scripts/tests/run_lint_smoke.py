#!/usr/bin/env python3
"""Smoke tests for the code-quality-mentor lint_markdown wrapper.

Exercises the vendored PyMarkdown tree, the pre-pass checks for issues
PyMarkdown silently accepts, the `LEARNING_PLAN.md` schema check, and
`--fix` mode end-to-end. Exits 0 if all tests pass; non-zero on the first
failure with a summary.

The bats suite (`run.sh`) covers the bash helpers; this Python file is the
parallel coverage for the Python linter wrapper.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent
LINTER = SCRIPTS / 'lint_markdown.py'
PYTHON = sys.executable


def run(*args):
    result = subprocess.run(
        [PYTHON, str(LINTER), *args], capture_output=True, text=True,
    )
    return result.returncode, result.stdout, result.stderr


def write(d, name, content_bytes):
    p = Path(d) / name
    p.write_bytes(content_bytes)
    return p


def test_clean_file_passes():
    with tempfile.TemporaryDirectory() as d:
        p = write(d, 'doc.md', b"# Title\n\nbody\n")
        rc, out, err = run(str(p))
        assert rc == 0, f"clean: rc={rc} out={out!r} err={err!r}"
        assert out == '', f"clean: stdout should be empty, got {out!r}"


def test_vendored_tree_loads():
    with tempfile.TemporaryDirectory() as d:
        p = write(d, 'doc.md', b"# Title\n\nbody\n")
        rc, _out, err = run(str(p))
        assert rc == 0, f"vendored tree load failed: err={err!r}"


def test_pre_pass_crlf():
    with tempfile.TemporaryDirectory() as d:
        p = write(d, 'doc.md', b"# Title\r\n\r\nbody\r\n")
        rc, out, _err = run(str(p))
        assert rc == 1, f"crlf: rc={rc}"
        assert 'crlf-line-endings' in out, f"crlf: {out!r}"


def test_pre_pass_unclosed_fence():
    with tempfile.TemporaryDirectory() as d:
        p = write(d, 'doc.md', b"# Title\n\n```python\nfoo\n")
        rc, out, _err = run(str(p))
        assert rc == 1, f"fence: rc={rc}"
        assert 'unclosed-fence' in out, f"fence: {out!r}"


def test_pre_pass_unclosed_frontmatter():
    with tempfile.TemporaryDirectory() as d:
        p = write(d, 'doc.md', b"---\nname: test\n\n# Title\n\nbody\n")
        rc, out, _err = run(str(p))
        assert rc == 1, f"frontmatter: rc={rc}"
        assert 'unclosed-frontmatter' in out, f"frontmatter: {out!r}"


def test_pymarkdown_rule_fires():
    with tempfile.TemporaryDirectory() as d:
        # MD022 — heading not surrounded by blank lines.
        p = write(d, 'doc.md', b"# Title\nimmediately after H1\n")
        rc, out, _err = run(str(p))
        assert rc == 1, f"md022: rc={rc}"
        assert 'md022' in out, f"md022: {out!r}"


def test_schema_rule_section_missing_subsection():
    content = (
        b"# Learning plan for Test Author\n\n"
        b"- **Author:** Test <t@example.com>\n\n"
        b"## Profile\n\nProfile prose.\n\n"
        b"## ExampleRule\n\n"
        b"- **Family:** error-prone\n\n"
        b"### Concept\n\nConcept prose.\n\n"
        b"### Why it matters here\n\nMatters prose.\n\n"
        b"### Evidence\n\n```\nx\n```\n\n"
        b"### Further reading\n\n- ref\n\n"
        b"## Habits going forward\n\n- habit\n"
    )
    with tempfile.TemporaryDirectory() as d:
        p = write(d, 'LEARNING_PLAN.md', content)
        rc, out, _err = run(str(p))
        assert rc == 1, f"schema: rc={rc}"
        assert 'rule-section-missing-subsection' in out, f"schema: {out!r}"
        assert 'Refactoring' in out, \
            f"schema: missing subsection name not surfaced: {out!r}"


def test_schema_rule_section_clean_passes():
    content = (
        b"# Learning plan for Test Author\n\n"
        b"- **Author:** Test <t@example.com>\n\n"
        b"## Profile\n\nProfile prose.\n\n"
        b"## ExampleRule\n\n"
        b"- **Family:** error-prone\n\n"
        b"### Concept\n\nConcept prose.\n\n"
        b"### Why it matters here\n\nMatters prose.\n\n"
        b"### Refactoring\n\nRefactor prose.\n\n"
        b"### Evidence\n\n```text\nx\n```\n\n"
        b"### Further reading\n\n- ref\n\n"
        b"## Habits going forward\n\n- habit\n"
    )
    with tempfile.TemporaryDirectory() as d:
        p = write(d, 'LEARNING_PLAN.md', content)
        rc, out, _err = run(str(p))
        assert rc == 0, f"clean schema: rc={rc} out={out!r}"


def test_schema_skips_profile_and_habits_sections():
    # Profile and Habits going forward are not rule sections; missing
    # subsections in them must not be flagged.
    content = (
        b"# Learning plan for Test Author\n\n"
        b"- **Author:** Test <t@example.com>\n\n"
        b"## Profile\n\nProfile prose, no H3 subsections.\n\n"
        b"## Habits going forward\n\n- habit, no H3 subsections.\n"
    )
    with tempfile.TemporaryDirectory() as d:
        p = write(d, 'LEARNING_PLAN.md', content)
        rc, out, _err = run(str(p))
        assert rc == 0, f"non-rule sections: rc={rc} out={out!r}"


def test_fix_mode_normalizes():
    content = b"# Title\n\n\n\n\nbody\nmore"
    with tempfile.TemporaryDirectory() as d:
        p = write(d, 'doc.md', content)
        rc, out, err = run('--fix', str(p))
        assert rc == 0, f"fix: rc={rc} out={out!r} err={err!r}"
        fixed = p.read_bytes()
        assert fixed.endswith(b'\n'), f"fix: missing trailing newline: {fixed!r}"
        import re as _re
        assert not _re.search(rb'\n{4,}', fixed), \
            f"fix: still has >2 consecutive blank lines: {fixed!r}"


TESTS = [
    test_clean_file_passes,
    test_vendored_tree_loads,
    test_pre_pass_crlf,
    test_pre_pass_unclosed_fence,
    test_pre_pass_unclosed_frontmatter,
    test_pymarkdown_rule_fires,
    test_schema_rule_section_missing_subsection,
    test_schema_rule_section_clean_passes,
    test_schema_skips_profile_and_habits_sections,
    test_fix_mode_normalizes,
]


def main():
    failed = 0
    for t in TESTS:
        try:
            t()
            print(f"PASS  {t.__name__}")
        except AssertionError as e:
            print(f"FAIL  {t.__name__}: {e}", file=sys.stderr)
            failed += 1
        except Exception as e:
            print(f"ERROR {t.__name__}: {type(e).__name__}: {e}", file=sys.stderr)
            failed += 1
    if failed:
        print(f"\n{failed}/{len(TESTS)} failure(s)", file=sys.stderr)
        return 1
    print(f"\nAll {len(TESTS)} tests passed.")
    return 0


if __name__ == '__main__':
    sys.exit(main())
