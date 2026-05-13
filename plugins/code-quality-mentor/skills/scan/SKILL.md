---
name: scan
description: Scan a git repository with PMD plus an LLM-based antipattern scan driven by the bundled catalog, attribute each finding to its git-blame author, ask the user to select one developer, and synthesize a tailored LEARNING_PLAN.md with concept explanations, refactor sketches of the author's actual flagged code, and pointers to canonical references. Use when the user asks to scan a codebase for code-quality issues, build a personalized learning plan from static analysis findings, or coach a specific developer based on their characteristic warnings. Writes intermediate JSON reports under .code-quality-mentor/ and a final LEARNING_PLAN.md at the repo root.
version: 0.4.0
license: MIT
---

# Code Quality Mentor — Scan Mode

This skill turns PMD warnings — plus an LLM-driven antipattern scan that fills the gap PMD's rule engine cannot — into a personalized learning plan for one developer on a team. PMD tells you *what* mechanical issues are in the code; the catalog-driven LLM scan looks for design smells and antipatterns PMD does not detect; `git blame` tells you *who* wrote it. This skill closes the loop: it picks one author, derives their characteristic code quality blind spots from the merged findings on their lines, and writes a tailored `LEARNING_PLAN.md` with concept explanations, refactor sketches of their actual code, and verified external pointers.

**Audience and tone.** The default user is a developer reviewing their own warnings to improve. Frame findings as learning opportunities. A learning plan is not a performance review. The plan is a coaching artifact: direct, concise, and oriented toward *understanding* concepts rather than just fixing lines.

**No meta-commentary.** When you progress through this workflow, state the action you are taking, not the harness rule that permits it. Never write things like "since the user disabled pauses", "per the skill I'll proceed with the default", or "as instructed I'll skip the prompt." If a prompt is suppressed by session state, just proceed silently with the documented default. The user sees the action; the scaffolding is internal.

## When to use

Invoke this skill when the user:

1. Runs `/code-quality-mentor:scan` from inside a git repository.
2. Asks to scan a codebase for PMD and antipattern findings and learn from them.
3. Asks to build a personalized code quality learning plan from static analysis findings.

Do **not** invoke this skill for unrelated review work that does not involve code-quality findings or git history. If the user wants a generic code review or a security audit, use a different tool.

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

6. **Decide on the LLM antipattern scan.** Use `AskUserQuestion` to offer:
   - "Run the LLM antipattern scan" (default) — scans both PMD-flagged files and a sample of the largest source files.
   - "Run only on PMD-flagged files" — cheaper; scope is the files PMD already touched.
   - "Skip" — proceed with PMD findings alone.

   If the broader session has suppressed prompts, silently proceed with the default — do **not** narrate the reason (no "since the user disabled pauses", no "per the skill I'll proceed with the default"). Just continue. Skip this step entirely if PMD found zero violations *and* the user has explicitly asked for a PMD-only run.

7. **Run the LLM antipattern scan.** Skip if step 6 chose "Skip". Otherwise:
   - Read `${CLAUDE_SKILL_DIR}/../../shared/antipatterns.json` and `${CLAUDE_SKILL_DIR}/../../scripts/llm_scan_prompt.md`. The prompt file is the canonical specification of how you (Claude) carry out the scan; follow it.
   - The output is `$REPO_ROOT/.code-quality-mentor/llm-scan-report.json`, written with the `Write` tool, in PMD-shape JSON (`{formatVersion, pmdVersion: "llm-scan-<catalog.version>", files: [{filename, violations: [...]}]}`).
   - If the scan ends with an empty `files` array, that is fine — write the wrapper anyway so the next step has a stable input.

8. **Merge findings.** If `llm-scan-report.json` exists, run `${CLAUDE_SKILL_DIR}/../../scripts/merge_reports.sh "$REPO_ROOT/.code-quality-mentor/findings-report.json" "$REPO_ROOT/.code-quality-mentor/pmd-report.json" "$REPO_ROOT/.code-quality-mentor/llm-scan-report.json"`. Otherwise copy the PMD report to `findings-report.json` (so the next step has a stable input path). If the combined report contains zero violations, congratulate the user and stop.

9. **Attribute warnings.** Run `${CLAUDE_SKILL_DIR}/../../scripts/blame_warnings.sh "$REPO_ROOT" "$REPO_ROOT/.code-quality-mentor/findings-report.json"`. This writes `$REPO_ROOT/.code-quality-mentor/blame-report.json` (an array of authors with their warnings, sorted by warning count descending). If the array is empty, tell the user findings exist but `git blame` could not attribute any of them (possible if all flagged files were deleted in HEAD) and stop.

10. **Author selection.** Read the blame report. **If exactly one author has attributable warnings**, skip the question entirely: tell the user "Only <name> has attributable warnings; using them" and continue. **Otherwise**, use `AskUserQuestion` to present the top authors. Build options as `<Name> <<email>>: N warnings`. The tool supports up to 4 options. Use the first three slots for the top three authors by warning count. Use the fourth slot for "Show full list". When the user picks "Show full list", render a numbered list inline and ask them to reply with a number or with `name <email>` directly. The tool's automatic "Other" fallback also lets them type a name or email directly.

11. **Tailoring.** Use `AskUserQuestion` to gather three preferences, one question at a time. **These three questions are mandatory and must always be asked**, even if the broader session has instructed the agent to "work without stopping" or "skip clarifying questions". They are not clarifications — they are inputs to the artifact's shape. The depth, focus, and seniority answers materially change what `LEARNING_PLAN.md` covers, and silently picking defaults produces a generic plan rather than a tailored one. Do not invent a "no-pause" or "non-interactive" exception.

    - **Depth.** Options: "Terse — top 3 rules", "Standard — top 4 rules", "Deeper — top 5 rules". This drives how many rules the plan covers.
    - **Focus area.** Options: "Whatever is most frequent in their warnings" (default), "Best practices and error-prone code", "Design and maintainability", "Performance and security". When the user picks a focus area, filter the author's warnings by the matching PMD ruleset or catalog `family` before ranking.
    - **Seniority framing.** Options: "Junior — explain fundamentals", "Mid-level — concise, link to deeper sources", "Senior — assume the basics, focus on edge cases and tradeoffs". This drives prose tone, not content scope.

12. **Pick the rules.** From the selected author's warnings (filtered by focus area when applicable), count occurrences per `rule` and take the top N (3, 4, or 5 from the depth choice). If fewer distinct rules exist than N, just use what is available; do not pad. Treat PMD rule names (e.g., `EmptyCatchBlock`) and catalog antipattern ids (e.g., `long_method`) as the same kind of identifier; both are first-class entries in the count. When a catalog id is selected, read its entry from `shared/antipatterns.json` and use the catalog's `description`, `refactoring`, `language_notes`, and `canonical_references` as the source material for the corresponding LEARNING_PLAN section.

13. **Read the author's flagged code.** For each selected rule, pick 1 or 2 representative warnings, by default the most recent two by file modification time, unless one offers a materially different angle than the other (different pattern, different file type). For each chosen warning, use the `Read` tool with the warning's `line` (and the line range of `beginline` to `endline` when the report provides it) to read the actual source snippet plus a few lines of surrounding context. Quote the snippet verbatim; do not invent code.

14. **Synthesize `LEARNING_PLAN.md`.** Target **1200–2000 words total** (a 5–8 minute read). The plan is a coaching artifact, not a lint report. Concepts come first; code is evidence. The structure below is mechanical so the plan is both readable and parseable — a downstream tool can split on the headings and field markers, and a future revise mode can act on findings.

    ```markdown
    # Learning plan for <Author Name>

    - **Author:** <Name> <<email>>
    - **Findings reviewed:** <N>
    - **Rules covered:** <N>
    - **Depth:** <terse | standard | deeper>
    - **Focus:** <focus area>
    - **Seniority framing:** <junior | mid-level | senior>

    ## Profile

    <One paragraph, 3–5 sentences. Theme the patterns by *concept*, not by rule name. Example: "Your warnings cluster around two themes: exception handling as control flow (EmptyCatchBlock, AvoidThrowingRawExceptionTypes) and unclear ownership of state (UnusedPrivateField, DataClass). Both come back to making the program's intent visible from the code.">

    ---

    ## <rule_id>

    - **Family:** <catalog family, e.g., Bloaters / Couplers / OO Abusers; or PMD ruleset>
    - **Source:** <catalog | PMD>
    - **Occurrences:** <N>
    - **Locations:**
      - `<file:line>` — <one-sentence cite of the specific signal seen here>
      - `<file:line>` — ...

    ### Concept

    <3–5 sentences explaining the underlying design principle and the named refactoring vocabulary (e.g., "Extract Function", "Encapsulate Variable", "Replace Conditional with Polymorphism"). Plain prose; no bold paragraph leads inside this subsection.>

    ### Why it matters here

    <2–4 sentences. Specific consequence in *this* codebase — name the file, the call site, the kind of change that would break next. Plain prose.>

    ### Refactoring

    <2–4 sentences. The named refactoring + the specific shape it would take here (concrete class names, method names, file moves). Plain prose.>

    ### Evidence

    ```<language>
    // <relative-path>:<line>
    <one verbatim snippet, 3–8 lines, drawn via the `Read` tool from the author's actual flagged file>
    ```

    ### Further reading

    - **<Author, *Title*, ed., year, chapter/section + page if known.>**

      <Two- to four-sentence paraphrase (or short excerpt) that captures the specific idea this reference contributes. Label paraphrases as such — do not assert verbatim quotes you cannot verify. The reader should be able to see *what is in there* without leaving the document.>

      Applies here: <one sentence connecting the reference's idea to this finding>.

    - [<short link title, e.g., "refactoring.guru: Long Method">](<URL>) — <one-line description of what is at the URL, e.g., "quick lookup if you do not have the book at hand">

    Every URL goes inside `[title](url)`. Never write a raw URL, a bolded URL (`**https://...**`), or `<https://...>`. The link title is short and human-readable; the description is what is at the URL and why it is useful. The same rule applies to a URL that supplements a book/paper citation (e.g., a conference talk's video) — wrap it as `[video, ~30 min](url)`, not as a trailing bare URL.

    ---

    ## <rule_id_2>
    ... (same shape as above)

    ---

    ## Habits going forward

    - <2–4 short, concrete *thinking* habits, not just commands. Example: "Before you write a `try`/`catch`, ask: am I genuinely recovering, or am I hiding a failure? If you cannot answer the first half, let the exception propagate.">
    ```

    Each rule section targets ~300–450 words once metadata, prose subsections, evidence snippet, and Further reading are combined.

15. **Critical content rules.**
    - **Lead with the concept, not the code.** The first paragraph of every rule section explains the underlying principle in plain language; the code snippet appears later, as evidence that the principle was violated *here*. If a reader can skip the code and still understand the lesson, the section is doing its job.
    - **Name the principle.** Every concept paragraph should name an existing design principle, refactoring, or heuristic — "fail fast", "tell don't ask", "single responsibility", "Extract Method", "Replace Type Code with Subclasses". Catalog entries already carry their `refactoring` field; use it. PMD rules map to the same vocabulary even when the rule name does not.
    - **Use verbatim snippets** from the `Read` tool. Do not invent or paraphrase the author's code. Keep snippets short — 3 to 8 lines, with one or two lines of surrounding context.
    - **For PMD rules**, construct the docs URL deterministically using the per-language `pmd_docs_base_url` from `../../shared/pmd-languages.json` and the rule name as the anchor (e.g., `https://docs.pmd-code.org/latest/pmd_rules_java_errorprone.html#emptycatchblock`). PMD anchor names are lowercase. If unsure of the exact category for a rule, list the language-level docs URL instead — never fabricate.
    - **For catalog antipatterns**, use the entry's `canonical_references` directly. Every reference in the catalog already carries a URL.
    - **Every rule section must include at least one canonical non-tool reference** in "Further reading" — a specific *Refactoring* / *Effective Java* / *Clean Code* item, a peer-reviewed paper with full title and year, or a named conference talk with speaker and venue. Tool docs alone are not enough. For catalog antipatterns this is automatic (the catalog ships them). For PMD rules, if you genuinely cannot recall a good canonical reference, say so in the plan rather than fabricating one.
    - **Never invent URLs.** Books and papers may be cited without a URL in LEARNING_PLAN.md when the title + author + section is enough to locate them.

16. **Write the file.** Write `LEARNING_PLAN.md` to `$REPO_ROOT/LEARNING_PLAN.md`. Report the path back to the user, along with a one-line summary like: "Learning plan written for <Author Name> covering <N> rules across <M> warnings."

17. **Slop carve-out check.** Read `${CLAUDE_SKILL_DIR}/../../shared/slop-checks.md`. The file lists a small set of focused checks against AI-slop tropes specific to coaching-artifact prose. Re-read the `LEARNING_PLAN.md` you just wrote and apply each check; if you find any matches, rewrite the offending passages in place and overwrite the file. The carve-out is in-skill and focused on purpose: do not depend on or vendor the `ai-slop` plugin, and do not extend the carve-out beyond the cap stated in the file.

    Write findings to `$REPO_ROOT/.code-quality-mentor/slop-report.json` as a list of `{rule_id, file, line, quote, suggested_revision}` records (PMD-shape adjacent; a future revise mode can act on it). The `rule_id` matches the H2 heading in `slop-checks.md` (e.g., `anti-copula`, `em-dash-budget`). If the list is empty, write an empty array `[]`. Leave the slop report on disk for transparency even after fixing the plan.

## Argument handling

This command takes no positional arguments. It always operates on the enclosing git repository of the current working directory.

## Failure modes (graceful exits)

- Not in a git repository: stop with a clear message; do not proceed.
- Missing prerequisite tool: stop with the install hint from `check_prereqs.sh`.
- No PMD-supported language detected: stop and tell the user; suggest they confirm the file extensions are not being filtered out by `.gitattributes` or vendored-file rules.
- PMD reports zero violations *and* the LLM scan emits no findings (or was skipped): congratulate the user and exit cleanly. No `LEARNING_PLAN.md` written.
- All findings unattributable (e.g., flagged files deleted in HEAD): stop and tell the user; do not write a plan.

## Files this skill reads

- `${CLAUDE_SKILL_DIR}/../../shared/pmd-languages.json` — the Linguist→PMD language map.
- `${CLAUDE_SKILL_DIR}/../../shared/antipatterns.json` — the catalog of antipatterns and code smells the LLM scan applies.
- `${CLAUDE_SKILL_DIR}/../../shared/slop-checks.md` — the slop carve-out applied as a post-pass to the freshly written LEARNING_PLAN.md.
- `${CLAUDE_SKILL_DIR}/../../scripts/llm_scan_prompt.md` — the prompt template that defines the LLM scan's procedure and output contract.

## Files this skill writes

- `$REPO_ROOT/.code-quality-mentor/pmd-report.json` — always
- `$REPO_ROOT/.code-quality-mentor/llm-scan-report.json` — when the LLM antipattern scan is not skipped
- `$REPO_ROOT/.code-quality-mentor/findings-report.json` — merged PMD + LLM scan (or a copy of `pmd-report.json` when the LLM scan was skipped)
- `$REPO_ROOT/.code-quality-mentor/blame-report.json`
- `$REPO_ROOT/LEARNING_PLAN.md`
- `$REPO_ROOT/.code-quality-mentor/slop-report.json` — findings from the slop carve-out check on the generated plan (empty array `[]` when clean)

It does not modify any source file in the user's repository.
