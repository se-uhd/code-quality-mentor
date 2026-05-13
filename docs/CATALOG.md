# Maintaining the antipattern catalog

This document is for plugin maintainers. End users do not edit the catalog — they consume it through `/code-quality-mentor:scan`.

The catalog lives at `plugins/code-quality-mentor/skills/scan/assets/antipatterns.json` and ships with the plugin. The LLM antipattern scan reads it at run time, so additions and corrections take effect on the next scan after a plugin update.

## What the catalog is

A curated list of antipatterns and code smells PMD's rule engine does not catch — design smells, architectural antipatterns, language idiom violations. Each entry is a structured concept (id, family, description, detection signals, language notes, refactoring, canonical references). The LLM scan uses the `llm_detection_signals` to recognize matches in source code and emits findings in the same PMD-shape JSON the rest of the pipeline consumes.

The catalog deliberately avoids smells PMD already nails. Each entry's `pmd_overlap` documents the boundary so the scan can de-duplicate at run time.

## Schema

The full schema is `plugins/code-quality-mentor/skills/scan/assets/antipatterns.schema.json`. Highlights:

- **Top level**: `version`, `lastUpdated`, `sources[]`, `entries[]`.
- **Sources**: each upstream taxonomy (Fowler, refactoring.guru, SourceMaking, Detekt, etc.) gets one `sources[]` entry with `id`, `title`, and a resolvable `url`. URLs are mandatory — provenance is auditable.
- **Entries**: each smell carries `id` (snake_case), `name`, `family` (one of Fowler's five plus "Architecture"), `description`, `llm_detection_signals` (≥2 concrete cues), optional `language_notes`, `refactoring`, optional `pmd_overlap`, `seeded_from` (references into `sources[]`), and `canonical_references[]`.
- **Canonical references**: every reference carries a `url`. At least one per entry must be non-`tool_docs` (book/paper/talk/web) so each smell has a real conceptual citation.

## Updating the catalog

The script at `plugins/code-quality-mentor/skills/scan/scripts/update_catalog.sh` is the maintainer tool. It is not exposed as a slash command.

```bash
scripts/update_catalog.sh validate
scripts/update_catalog.sh refresh-refs
scripts/update_catalog.sh refresh-refs --offline
scripts/update_catalog.sh diff-upstream
```

- **validate** — schema and provenance checks. Run before every commit that touches `antipatterns.json`. Also runs in CI via the bats suite. Exits non-zero on failure with a one-line pointer to the offending entry.
- **refresh-refs** — HEAD-checks every URL in `sources[]` and `entries[].canonical_references[]`, reports any non-2xx as "needs review". Read-only. The `--offline` variant just counts URLs without making network calls.
- **diff-upstream** — compares entry names against pinned snapshots in `plugins/code-quality-mentor/skills/scan/assets/upstream_snapshots/*.json` and lists smells the snapshots cover but the catalog does not. Read-only. Snapshots are refreshed manually when upstream sources publish new smells.

## Adding a new entry

There is no interactive slash command — adding entries is a normal code change:

1. Decide which `sources[]` the entry is seeded from. If you cite a new upstream taxonomy, add it to `sources[]` first (id, title, url).
2. Append a new object to `entries[]` matching the schema. Look at existing entries (start with `long_method`) as a template.
3. Bump `lastUpdated` to today's ISO date.
4. Run `scripts/update_catalog.sh validate`. Fix any errors it reports.
5. Run the bats suite (`scripts/tests/run.sh`) to verify the schema-level tests still pass.
6. Commit. The standard repo conventions apply (terse subject, factual bullet body).

When drafting an entry, the most important field is `llm_detection_signals` — these are what the LLM scan actually matches against source code. Prefer structural signals ("method body > 30 lines", "field is null for most of the object's lifetime") over vibes. Two signals are the minimum; four is a good target. Each entry's pedagogy obligation is one resolvable canonical reference URL per `canonical_references[]` item, and at least one non-tool reference per entry.

## Versioning the catalog

The catalog's `version` field tracks the same SemVer as `plugin.json` and the scan skill's `SKILL.md` frontmatter. All three move in lockstep on every release so consumers see one number, not three. When you change the catalog:

- **patch** when entries gain new detection signals or canonical references but their `id`/`name`/`family` is unchanged.
- **minor** when entries are added or renamed (consumers using catalog ids may need to rebind learning-plan templates).
- **major** when the schema itself changes in a breaking way (consumers must adapt their JSON readers).

Bump `plugin.json` and `SKILL.md` to the same number in the same commit. The plugin's `pmdVersion: "llm-scan-<catalog.version>"` in the emitted report carries that number into every finding, so the version is auditable from the scan output without having to inspect the manifest.
