# Changelog

All notable changes to this plugin are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the plugin uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.4] — 2026-10-29

### Changed in 0.6.4

- Synced the vendored PyMarkdown linter to pymarkdown-skill 0.3.0 (PyMarkdown 0.9.40).

## [0.6.3] — 2026-06-11

### Changed in 0.6.3

- Synced the vendored PyMarkdown linter to pymarkdown-skill 0.2.2, so `lint_markdown.py` no longer reports a file as clean when PyMarkdown cannot scan it. Also corrected the `skills/scan/SKILL.md` version field, which the 0.6.2 release left at 0.6.1.

## [0.6.1] — 2026-05-14

### Changed in 0.6.1

- Disabled md024 (no-duplicate-heading) in `skills/scan/scripts/lint_markdown.yaml`. The rule flagged every well-formed `LEARNING_PLAN.md`, because the plan schema repeats the same subsection headings under every rule.

## [0.6.0] — 2026-05-14

### Added in 0.6.0

- Vendored PyMarkdown (pure-Python, ~4.5 MB) under `skills/scan/scripts/_vendor/`, with a `lint_markdown.py` wrapper and a `refresh_vendor.py` maintainer script. The wrapper also flags CR/CRLF, unclosed fences, and unclosed frontmatter, which PyMarkdown accepts silently, and requires the five subsections `Concept`, `Why it matters here`, `Refactoring`, `Evidence`, and `Further reading` under every rule heading of `LEARNING_PLAN.md`.
- New workflow step 18 in the `scan` skill lints the freshly written `LEARNING_PLAN.md` with `--fix` and a three-iteration revise loop. This internal quality control is not shown to the user.
- Smoke tests for the linter at `skills/scan/scripts/tests/run_lint_smoke.py`, run in both the light and full CI jobs.

### Changed in 0.6.0

- `SKILL.md` step 14 now requires a language tag on every Evidence code block, which avoids an md040 lint iteration.
- README, SKILL.md, CHANGELOG, and the two `references/` files cleaned up to satisfy the new linter (fence language tags, blank-line spacing around headings and lists).

## [0.5.0] — 2026-05-13

### Changed

- The layout now follows the [Agent Skills specification](https://agentskills.io/specification). The plugin-level `scripts/` and `shared/` directories moved inside the skill folder under the canonical names from the spec:
  - `scripts/*.sh` -> `skills/scan/scripts/`
  - `shared/pmd-languages.json`, `shared/antipatterns.json`, `shared/antipatterns.schema.json` -> `skills/scan/assets/`
  - `shared/llm_scan_prompt.md`, `shared/slop-checks.md` -> `skills/scan/references/`
  - `scripts/tests/` -> `skills/scan/scripts/tests/`
- Updated all path references in `SKILL.md`, `scripts/*.sh`, `commands/scan.md`, the bats test suite, `README.md`, and `docs/CATALOG.md`.
- `SKILL.md` paths now use `${CLAUDE_SKILL_DIR}/{scripts,assets,references}/...` instead of `${CLAUDE_SKILL_DIR}/../../{scripts,shared}/...`.

### Migration

- Existing scripts that hard-coded `plugins/code-quality-mentor/shared/...` or `plugins/code-quality-mentor/scripts/...` must update to the new paths.
- The `$id` URL in `antipatterns.schema.json` changed accordingly. No consumer in this repo reads it programmatically.

## [0.4.0] — 2026-05-13

### Added

- `shared/slop-checks.md`: a carve-out of up to ~15 AI-slop tropes specific to coaching-artifact prose, such as invented concept labels and anthropomorphizing. It is part of the skill and does not require the `ai-slop` plugin.
- New workflow step 17 in the `scan` skill, the internal "Slop carve-out check", re-reads the just-written `LEARNING_PLAN.md` and fixes matches from `shared/slop-checks.md` in place. It writes no report file and does not show findings to the user.

### Changed in 0.4.0

- The `LEARNING_PLAN.md` template (step 14) is now structured instead of free-form, so downstream parsers can split on its headings and field markers. Each rule section has a `## <rule_id>` heading without an editorial subtitle; a metadata block with the fields `Family`, `Source`, `Occurrences`, and `Locations`; the prose subsections `Concept`, `Why it matters here`, `Refactoring`, and `Evidence`; and `Further reading` entries that must each paraphrase what the linked resource contains in 2–4 sentences.
- Raised the total word target from 600–1200 to 1200–2000 words, with 300–450 words per rule section.
- URLs in the plan must use `[title](url)` markdown syntax. Raw URLs, bolded URLs (`**https://...**`), and angle-bracket links are disallowed.
- Updated the plugin version in `.claude-plugin/marketplace.json` from 0.2.0 to 0.4.0, because the 0.3.0 release shipped a stale marketplace entry.

## [0.3.0]

Initial public release of the structured workflow (PMD + catalog-driven LLM scan, git-blame attribution, tailored learning plan).
