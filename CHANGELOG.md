# Changelog

All notable changes to this plugin are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the plugin uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.1] — 2026-05-14

### Changed in 0.6.1

- Disable md024 (no-duplicate-heading) in `skills/scan/scripts/lint_markdown.yaml`. The `LEARNING_PLAN.md` schema repeats the five subsection headings (`Concept`, `Why it matters here`, `Refactoring`, `Evidence`, `Further reading`) under every rule, so md024 fires on every well-formed plan.

## [0.6.0] — 2026-05-14

### Added in 0.6.0

- Vendored PyMarkdown (pure-Python, ~4.5 MB) under `skills/scan/scripts/_vendor/` with a `lint_markdown.py` wrapper and `refresh_vendor.py` maintainer script. `pyjson5` is replaced by a stdlib shim because PyMarkdown is invoked with `--no-json5`. The wrapper applies a pre-pass for CR/CRLF, unclosed fences, and unclosed frontmatter (rules PyMarkdown silently accepts) plus a `LEARNING_PLAN.md` schema check that requires the five named subsections (`Concept`, `Why it matters here`, `Refactoring`, `Evidence`, `Further reading`) under every rule heading.
- New workflow step 18 in `scan` skill: lint the freshly written `LEARNING_PLAN.md` with `--fix` and a three-iteration revise loop. Internal quality control; not surfaced to the user.
- Smoke tests at `skills/scan/scripts/tests/run_lint_smoke.py` covering vendored-tree load, pre-pass rules, schema rule, and `--fix`-mode normalization. CI runs them in both the light and full jobs.

### Changed in 0.6.0

- `SKILL.md` step 14: tightened the Evidence-fence directive so the model always tags the code-block language (avoids an md040 lint iteration).
- README, SKILL.md, CHANGELOG, and the two `references/` files cleaned up to satisfy the new linter (fence language tags, blank-line spacing around headings and lists).

## [0.5.0] — 2026-05-13

### Changed

- **Layout now follows the [Agent Skills specification](https://agentskills.io/specification).** The plugin-level `scripts/` and `shared/` directories have been moved inside the skill folder, using the canonical names from the spec:
  - `scripts/*.sh` → `skills/scan/scripts/`
  - `shared/pmd-languages.json`, `shared/antipatterns.json`, `shared/antipatterns.schema.json` → `skills/scan/assets/`
  - `shared/llm_scan_prompt.md`, `shared/slop-checks.md` → `skills/scan/references/`
  - `scripts/tests/` → `skills/scan/scripts/tests/`
- All path references updated in `SKILL.md`, `scripts/*.sh`, `commands/scan.md`, the bats test suite, `README.md`, and `docs/CATALOG.md`. The 56-test bats suite passes against the new layout.
- `SKILL.md` paths now use `${CLAUDE_SKILL_DIR}/{scripts,assets,references}/...` (one level deep from the skill root) instead of `${CLAUDE_SKILL_DIR}/../../{scripts,shared}/...`.

### Migration

- Existing scripts that hard-coded `plugins/code-quality-mentor/shared/...` or `plugins/code-quality-mentor/scripts/...` must update to the new paths.
- The `$id` URL in `antipatterns.schema.json` changed accordingly; no consumer reads it programmatically inside this repo.

## [0.4.0] — 2026-05-13

### Added

- `shared/slop-checks.md`: a focused carve-out of AI-slop tropes specific to coaching-artifact prose (anti-copula, invented concept labels, em-dash budget, anthropomorphizing, grounded references, no editorial subtitles on rule headings, no bold-first paragraph leads in prose subsections, proper markdown links). Capped at ~15 entries. The carve-out is in-skill; the `ai-slop` plugin is not a dependency.
- New workflow step in `scan` skill (step 17): internal "Slop carve-out check" reads `shared/slop-checks.md`, re-reads the just-written `LEARNING_PLAN.md`, and fixes matches in place. The check is an internal pre-publication scrub — no separate report file is written and findings are not surfaced to the user.

### Changed in 0.4.0

- `LEARNING_PLAN.md` template (step 14) is now structured rather than free-form: `## <rule_id>` heading (no editorial subtitle), metadata block with named fields (`Family`, `Source`, `Occurrences`, `Locations`), four named prose subsections (`Concept`, `Why it matters here`, `Refactoring`, `Evidence`), and `Further reading` with paraphrase-required entries (2–4 sentence excerpts that say *what is in there*). Downstream parsers can split on the headings and field markers.
- Word target raised from 600–1200 words to **1200–2000 words** total, with each rule section targeting 300–450 words.
- URLs in the plan must use `[title](url)` markdown syntax. Raw URLs, bolded URLs (`**https://...**`), and angle-bracket links are disallowed.
- `.claude-plugin/marketplace.json` plugin version caught up from 0.2.0 to 0.4.0; the 0.3.0 release shipped a stale marketplace entry.

## [0.3.0]

Initial public release of the structured workflow (PMD + catalog-driven LLM scan, git-blame attribution, tailored learning plan).
