---
name: scan
description: Scan a git repository with PMD, attribute each warning to its git-blame author, ask the user to select one developer, and synthesize a tailored LEARNING_PLAN.md with concept explanations, refactor sketches of the author's actual flagged code, and pointers to canonical references. Use when the user asks to scan a codebase for PMD violations, build a personalized learning plan from static analysis findings, or coach a specific developer based on their characteristic warnings. Writes intermediate JSON reports under .code-quality-mentor/ and a final LEARNING_PLAN.md at the repo root.
version: 0.1.0
license: MIT
---

# Code Quality Mentor — Scan Mode

This skill turns PMD warnings into a personalized learning plan for one developer on a team. PMD already tells you *what* is wrong with the code, and `git blame` already tells you *who* wrote it. This skill closes the loop: it picks one author, derives their characteristic code quality blind spots from PMD's findings on their lines, and writes a tailored `LEARNING_PLAN.md` with concept explanations, refactor sketches of their actual code, and verified external pointers.

**Audience and tone.** The default user is a developer reviewing their own warnings to improve. Frame findings as learning opportunities. A learning plan is not a performance review. The plan is a coaching artifact: direct, concise, and oriented toward *understanding* concepts rather than just fixing lines.

## When to use

Invoke this skill when the user:

1. Runs `/code-quality-mentor:scan` from inside a git repository.
2. Asks to scan a codebase for PMD violations and learn from them.
3. Asks to build a personalized code quality learning plan from static analysis findings.

Do **not** invoke this skill for unrelated review work that does not involve PMD or git history. If the user wants a generic code review or a security audit, use a different tool.

## Prerequisites

All required tools are checked by the bundled `check_prereqs.sh` script. Required:

- `java` (>=11) — PMD runtime
- `pmd` (>=7) — the source-level static analyzer
- `jq` — JSON manipulation
- `git` — repository history and blame
- One of: `github-linguist` (preferred) or `enry` — language detection

If anything is missing, the script prints platform-specific install hints and exits non-zero. Pass those hints through to the user and stop the workflow.

## Workflow

1. **Verify prerequisites.** Run `${CLAUDE_SKILL_DIR}/../../scripts/check_prereqs.sh`. On non-zero exit, surface the stderr to the user verbatim (it contains install hints) and stop.

2. **Locate the repo root.** Run `${CLAUDE_SKILL_DIR}/../../scripts/find_repo_root.sh`. On non-zero exit, tell the user the current directory is not inside a git repository and stop. Capture the printed path as `REPO_ROOT` for subsequent steps.

3. **Detect languages.** Run `${CLAUDE_SKILL_DIR}/../../scripts/detect_languages.sh "$REPO_ROOT"`. The output is a JSON array of detected PMD-supported languages, sorted by metric descending. If the array is empty, tell the user PMD has no default ruleset for any language present in the repo, and stop.

4. **Confirm language selection (optional).** If the array has more than one entry, use `AskUserQuestion` to confirm which languages to scan. The default option is "all detected languages." Provide up to three additional options for individual languages (the top three by metric). The "Other" branch the tool offers automatically lets the user type a custom subset.

5. **Run PMD.** Concatenate the `ruleset` fields of the selected languages with commas. Run `${CLAUDE_SKILL_DIR}/../../scripts/run_pmd.sh "$REPO_ROOT" "<ruleset-csv>"`. The script writes `$REPO_ROOT/.code-quality-mentor/pmd-report.json` and prints its path. On non-zero exit, surface the stderr log path to the user and stop.

6. **Stage findings.** Copy `pmd-report.json` to `findings-report.json` so the next step has a stable input path. If `pmd-report.json` contains zero violations, congratulate the user and stop.

7. **Attribute warnings.** Run `${CLAUDE_SKILL_DIR}/../../scripts/blame_warnings.sh "$REPO_ROOT" "$REPO_ROOT/.code-quality-mentor/findings-report.json"`. This writes `$REPO_ROOT/.code-quality-mentor/blame-report.json` (an array of authors with their warnings, sorted by warning count descending). If the array is empty, tell the user findings exist but `git blame` could not attribute any of them (possible if all flagged files were deleted in HEAD) and stop.

8. **Author selection.** Read the blame report. **If exactly one author has attributable warnings**, skip the question entirely: tell the user "Only <name> has attributable warnings; using them" and continue. **Otherwise**, use `AskUserQuestion` to present the top authors. Build options as `<Name> <<email>>: N warnings`. The tool supports up to 4 options. Use the first three slots for the top three authors by warning count. Use the fourth slot for "Show full list". When the user picks "Show full list", render a numbered list inline and ask them to reply with a number or with `name <email>` directly. The tool's automatic "Other" fallback also lets them type a name or email directly.

9. **Tailoring.** Use `AskUserQuestion` to gather three preferences, one question at a time. **These three questions are mandatory and must always be asked**, even if the broader session has instructed the agent to "work without stopping" or "skip clarifying questions". They are not clarifications — they are inputs to the artifact's shape. The depth, focus, and seniority answers materially change what `LEARNING_PLAN.md` covers, and silently picking defaults produces a generic plan rather than a tailored one. Do not invent a "no-pause" or "non-interactive" exception.

    - **Depth.** Options: "Terse — top 3 rules", "Standard — top 4 rules", "Deeper — top 5 rules". This drives how many rules the plan covers.
    - **Focus area.** Options: "Whatever is most frequent in their warnings" (default), "Best practices and error-prone code", "Design and maintainability", "Performance and security". When the user picks a focus area, filter the author's warnings by the matching PMD ruleset before ranking.
    - **Seniority framing.** Options: "Junior — explain fundamentals", "Mid-level — concise, link to deeper sources", "Senior — assume the basics, focus on edge cases and tradeoffs". This drives prose tone, not content scope.

10. **Pick the rules.** From the selected author's warnings (filtered by focus area when applicable), count occurrences per `rule` and take the top N (3, 4, or 5 from the depth choice). If fewer distinct rules exist than N, just use what is available; do not pad.

11. **Read the author's flagged code.** For each selected rule, pick 1 or 2 representative warnings, by default the most recent two by file modification time, unless one offers a materially different angle than the other (different pattern, different file type). For each chosen warning, use the `Read` tool with the warning's `line` (and the line range of `beginline` to `endline` when the report provides it) to read the actual source snippet plus a few lines of surrounding context. Quote the snippet verbatim; do not invent code.

12. **Synthesize `LEARNING_PLAN.md`.** Target **600–1200 words total** (a 3–5 minute read). Use this structure:

    ```markdown
    # Learning plan for <Author Name>

    <one-paragraph profile of the patterns observed in this author's warnings, neutral and specific — e.g., "Your warnings cluster around two themes: exception handling (3 occurrences of EmptyCatchBlock) and unused state (2 occurrences of UnusedPrivateField). Both are recoverable with light refactoring habits.">

    ## <RuleName 1>

    **Concept.** <2–4 sentences explaining what the rule guards against, in plain language.>

    **Why it matters.** <Concrete negative implications — bugs, performance, maintainability, security. Be specific to the rule.>

    **Idiomatic alternative.** <What to do instead, generically. One short paragraph.>

    **In your code.**
    ```<language>
    // <relative-path>:<line>
    <verbatim snippet>
    ```
    Refactored:
    ```<language>
    <refactored snippet>
    ```

    **Further reading.**
    - PMD: <verifiable URL of the form https://docs.pmd-code.org/latest/pmd_rules_<lang>_<category>.html#<rulename>>
    - <Canonical reference: book + chapter, paper title + venue + year, or named talk + speaker. Include a URL only when you are confident it resolves. If only a citation is given, that is fine — readers can locate it.>

    ## <RuleName 2>
    ...

    ## Habits going forward

    - <2–4 short, concrete habits — e.g., "Before committing Java code that touches exception handling, run `pmd check --rulesets category/java/quickstart.xml --dir <changed-files>`.">
    - <Optional: a pre-commit hook snippet, no more than 6 lines.>
    ```

    Cap each rule section at ~150–220 words. Use exactly one snippet per rule by default; use two only when the second illustrates a materially different angle.

13. **Critical content rules.**
    - **Use verbatim snippets** from the `Read` tool. Do not invent or paraphrase the author's code.
    - **Construct PMD URLs deterministically** using the per-language `pmd_docs_base_url` from `../../shared/pmd-languages.json` and the rule name as the anchor (e.g., `https://docs.pmd-code.org/latest/pmd_rules_java_errorprone.html#emptycatchblock`). PMD anchor names are lowercase. If unsure of the exact category for a rule, list the language-level docs URL instead — never fabricate.
    - **Every rule section must include at least one canonical non-PMD reference** in "Further reading" — a specific *Effective Java* item, a *Clean Code* chapter, a peer-reviewed paper with full title and year, or a named conference talk with speaker and venue. Tool docs alone are not enough. If you genuinely cannot recall a good canonical reference for a particular rule, say so in the plan ("PMD docs are the best single reference for this rule") rather than fabricating one.
    - **Never invent URLs.** Books and papers may be cited without a URL when the title + author + section is enough to locate them.

14. **Write the file.** Write `LEARNING_PLAN.md` to `$REPO_ROOT/LEARNING_PLAN.md`. Report the path back to the user, along with a one-line summary like: "Learning plan written for <Author Name> covering <N> rules across <M> warnings."

## Argument handling

This command takes no positional arguments. It always operates on the enclosing git repository of the current working directory.

## Failure modes (graceful exits)

- Not in a git repository → stop with a clear message; do not proceed.
- Missing prerequisite tool → stop with the install hint from `check_prereqs.sh`.
- No PMD-supported language detected → stop and tell the user; suggest they confirm the file extensions are not being filtered out by `.gitattributes` or vendored-file rules.
- PMD reports zero violations → congratulate the user and exit cleanly. No `LEARNING_PLAN.md` written.
- All warnings unattributable (e.g., flagged files deleted in HEAD) → stop and tell the user; do not write a plan.

## Files this skill reads

- `${CLAUDE_SKILL_DIR}/../../shared/pmd-languages.json` — the Linguist→PMD language map.

## Files this skill writes

- `$REPO_ROOT/.code-quality-mentor/pmd-report.json` — always
- `$REPO_ROOT/.code-quality-mentor/findings-report.json` — a copy of `pmd-report.json`
- `$REPO_ROOT/.code-quality-mentor/blame-report.json`
- `$REPO_ROOT/LEARNING_PLAN.md`

It does not modify any source file in the user's repository.
