# Changelog

All notable changes to this plugin are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the plugin uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] — 2026-05-13

### Added
- `shared/slop-checks.md`: a focused carve-out of AI-slop tropes specific to coaching-artifact prose (anti-copula, invented concept labels, em-dash budget, anthropomorphizing, grounded references, no editorial subtitles on rule headings, no bold-first paragraph leads in prose subsections, proper markdown links). Capped at ~15 entries. The carve-out is in-skill; the `ai-slop` plugin is not a dependency.
- New workflow step in `scan` skill (step 17): "Slop carve-out check" reads `shared/slop-checks.md`, re-reads the just-written `LEARNING_PLAN.md`, fixes matches in place, and writes findings to `.code-quality-mentor/slop-report.json`.
- New output artifact: `.code-quality-mentor/slop-report.json` with PMD-shape adjacent records `{rule_id, file, line, quote, suggested_revision}`.

### Changed
- `LEARNING_PLAN.md` template (step 14) is now structured rather than free-form: `## <rule_id>` heading (no editorial subtitle), metadata block with named fields (`Family`, `Source`, `Occurrences`, `Locations`), four named prose subsections (`Concept`, `Why it matters here`, `Refactoring`, `Evidence`), and `Further reading` with paraphrase-required entries (2–4 sentence excerpts that say *what is in there*). Downstream parsers can split on the headings and field markers.
- Word target raised from 600–1200 words to **1200–2000 words** total, with each rule section targeting 300–450 words.
- URLs in the plan must use `[title](url)` markdown syntax. Raw URLs, bolded URLs (`**https://...**`), and angle-bracket links are disallowed.
- `.claude-plugin/marketplace.json` plugin version caught up from 0.2.0 to 0.4.0; the 0.3.0 release shipped a stale marketplace entry.

## [0.3.0]

Initial public release of the structured workflow (PMD + catalog-driven LLM scan, git-blame attribution, tailored learning plan).
