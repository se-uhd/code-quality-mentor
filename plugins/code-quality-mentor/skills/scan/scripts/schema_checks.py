"""schema_checks.py — code-quality-mentor schema rule for LEARNING_PLAN.md.

One check:

  rule-section-missing-subsection   `LEARNING_PLAN.md`: a rule section
                                    (any H2 other than `Profile` or
                                    `Habits going forward`) is missing one
                                    of the five required H3 subsections
                                    (`Concept`, `Why it matters here`,
                                    `Refactoring`, `Evidence`,
                                    `Further reading`).

The plan H1 is matched by prefix (`Learning plan for `) since the heading
interpolates the author's name.

The linter (`lint_markdown.py`, synced from pymarkdown-skill) loads this
file via importlib and calls `schema_findings(text, path)` at lint time.
"""
import re

SKILL_NAME = "code-quality-mentor"

PLAN_H1_PREFIX = "Learning plan for "
NON_RULE_H2_BODIES = frozenset({"Profile", "Habits going forward"})
REQUIRED_SUBSECTIONS = (
    "Concept",
    "Why it matters here",
    "Refactoring",
    "Evidence",
    "Further reading",
)

HEADING_RE = re.compile(r'^(#{1,6})\s+(.*)$')
FENCE_OPENER_RE = re.compile(r'^(`{3,})')
FENCE_CLOSER_RE = re.compile(r'^(`{3,})\s*$')


def schema_findings(text, path):
    findings = []
    lines = text.split('\n')
    if lines and lines[-1] == '':
        lines = lines[:-1]

    in_fence = None
    in_frontmatter = lines and lines[0].strip() == '---'
    is_plan = False
    rule_sections = []
    current_section = None

    for i, line in enumerate(lines, 1):
        if in_frontmatter:
            if i > 1 and line.strip() == '---':
                in_frontmatter = False
            continue
        if in_fence is not None:
            m = FENCE_CLOSER_RE.match(line)
            if m and len(m.group(1)) >= in_fence:
                in_fence = None
            continue
        m = FENCE_OPENER_RE.match(line)
        if m:
            in_fence = len(m.group(1))
            continue

        hm = HEADING_RE.match(line)
        if hm:
            level = len(hm.group(1))
            body = hm.group(2).rstrip().rstrip('#').rstrip()
            if level == 1 and not is_plan:
                if body.startswith(PLAN_H1_PREFIX):
                    is_plan = True
            if level <= 2:
                if current_section is not None:
                    rule_sections.append(current_section)
                    current_section = None
                if level == 2 and body not in NON_RULE_H2_BODIES:
                    current_section = (i, body, [])
                continue
            if level == 3 and current_section is not None:
                current_section[2].append(body)

    if current_section is not None:
        rule_sections.append(current_section)

    if is_plan:
        for header_line, _body, subsections in rule_sections:
            present = set(subsections)
            for required in REQUIRED_SUBSECTIONS:
                if required not in present:
                    findings.append((
                        header_line, 'rule-section-missing-subsection',
                        f'rule section is missing `### {required}` subsection',
                    ))

    return findings
