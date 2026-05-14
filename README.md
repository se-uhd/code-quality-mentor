# code-quality-mentor

A Claude Code plugin that turns PMD warnings and an LLM-based antipattern scan into a personalized learning plan for one developer on a team.

PMD tells you *what* mechanical issues are in the code. The bundled catalog of antipatterns and code smells drives an LLM scan that catches design-level problems PMD's rule engine cannot reach: God classes, feature envy, primitive obsession, temporal coupling, and so on. `git blame` tells you *who* wrote the lines. The plugin closes the loop: it picks one author, derives their characteristic blind spots from the merged findings on their lines, and writes a tailored `LEARNING_PLAN.md` that leads with the underlying design principle and uses the author's actual code as evidence.

## What it does

The plugin provides one slash command:

```text
/code-quality-mentor:scan
```

The workflow runs end to end on the enclosing git repository:

1. Detects which PMD-supported languages are present, using GitHub Linguist (or `enry`).
2. Runs `pmd check` with sensible default rulesets for each detected language.
3. Asks whether to run the LLM antipattern scan. When you say yes, Claude reads the bundled catalog (`skills/scan/assets/antipatterns.json`) and looks across the PMD-flagged files (plus a sample of the largest source files) for the design smells PMD does not detect. It emits findings in PMD-shape JSON.
4. Merges PMD and LLM-scan findings into a single report (or uses PMD alone when you skip the LLM scan).
5. Attributes every finding's first line to a `git blame` author.
6. Asks you to pick one developer from the list, sorted by finding count.
7. Asks three tailoring questions: depth, focus area, and seniority framing.
8. Writes `LEARNING_PLAN.md` at the repo root: a 3-to-5-minute read covering the developer's top 3 to 5 issues. Each section leads with the underlying design principle (named refactoring, "tell don't ask", "fail fast", and so on), explains why it matters, and uses one verbatim snippet from the developer's flagged code as evidence. The concept paragraph is the longest paragraph; code illustrates the idea, never carries it.

Intermediate JSON reports live under `.code-quality-mentor/`. The plugin never modifies your source code.

## The antipattern catalog

The LLM scan is driven by `plugins/code-quality-mentor/skills/scan/assets/antipatterns.json`, a curated catalog of antipatterns and code smells. Each entry has an id, family (Bloaters, OO Abusers, Change Preventers, Dispensables, Couplers, Architecture), description, concrete detection signals, language-specific notes, named refactoring, and canonical references (book chapters, Fowler bliki pages, papers, talks; every reference carries a resolvable URL).

The catalog ships with the plugin. End users do not edit it; they consume it through `/code-quality-mentor:scan`. Plugin maintainers update it via the script at `plugins/code-quality-mentor/scripts/update_catalog.sh`; see [docs/CATALOG.md](docs/CATALOG.md) for the maintenance workflow.

## Supported languages

Every language for which PMD ships a rule-based ruleset (verified against [the PMD 7 rule reference](https://docs.pmd-code.org/latest/)):

Apex, HTML, Java, Java Server Pages, JavaScript, Kotlin, Maven POM, Modelica, PLSQL, Scala, Swift, Velocity Template Language, Visualforce, WSDL, XML, XSLT (the names match the Linguist language IDs used by `skills/scan/assets/pmd-languages.json`).

The plugin does not analyze languages that PMD parses for CPD (copy-paste detection) only: C/C++, C#, CSS, Dart, Fortran, Gherkin, Go, Groovy, Julia, Lua, Matlab, Objective-C, Perl, PHP, Python, Ruby, Rust, T-SQL, Coco. CPD finds duplication, not the rule-based warnings this plugin teaches from.

The language-to-ruleset map lives at `plugins/code-quality-mentor/skills/scan/assets/pmd-languages.json` and is straightforward to edit if you want a stricter or laxer default per language.

## Prerequisites

| Tool                          | Why                                       | Install (macOS)                                          |
| ----------------------------- | ----------------------------------------- | -------------------------------------------------------- |
| `java` (>=11)                 | PMD runtime                               | `brew install temurin`                                   |
| `pmd` (>=7)                   | Source-level static analyzer              | `brew install pmd`                                       |
| `jq`                          | JSON manipulation in the helper scripts   | `brew install jq`                                        |
| `git`                         | Repository history and `git blame`        | `xcode-select --install`                                 |
| `github-linguist` *or* `enry` | Language detection in the repo            | `gem install github-linguist` *or* `brew install enry`   |

Contributors who want to run the test suite also need `bats-core` (`brew install bats-core`).

The slash command calls `check_prereqs.sh` first and prints platform-specific install hints if anything is missing.

## Installation

In any Claude Code session:

```text
/plugin marketplace add se-uhd/code-quality-mentor
/plugin install code-quality-mentor
```

`se-uhd/code-quality-mentor` is the GitHub shorthand for `https://github.com/se-uhd/code-quality-mentor`; the full HTTPS or SSH URL works equally well. To install from a local clone instead of GitHub, pass the path to the clone directory: `/plugin marketplace add /path/to/code-quality-mentor`.

## Updating

To pull the latest version of the marketplace and refresh the installed plugin:

```text
/plugin marketplace update code-quality-mentor
```

This re-fetches the marketplace metadata from GitHub. After it completes, restart your Claude Code session (or run `/plugin install code-quality-mentor` again) so the updated plugin is picked up. To remove the plugin entirely: `/plugin uninstall code-quality-mentor`.

## Usage

`cd` into the Git repository you want to scan, then:

```text
/code-quality-mentor:scan
```

Answer the prompts. When the run finishes, open `LEARNING_PLAN.md` at the repo root.

Add the scratch directory to your project's `.gitignore`:

```text
.code-quality-mentor/
```

## Use in other Agent Skills clients

The plugin's logic is a single skill at `plugins/code-quality-mentor/skills/scan/`, structured per the [Agent Skills specification](https://agentskills.io/specification) (`SKILL.md` plus `scripts/`, `references/`, and `assets/`). To run it under another Agent Skills client (Cursor, GitHub Copilot, OpenAI Codex, Gemini CLI, JetBrains Junie; see the [client list](https://agentskills.io/clients) for the current set), copy that subtree into the location your client expects.

The skill drives the workflow through shell commands (`pmd check`, `git blame`, `jq`, and the helper bash scripts under `scripts/`), so the host client must allow a skill to execute shell commands. A client that only runs inline LLM prompts cannot run the full pipeline.

## Layout

Each skill is a self-contained folder with `SKILL.md` plus the optional `scripts/`, `references/`, and `assets/` subdirectories.

```text
.claude-plugin/marketplace.json   # marketplace entry (single-plugin)
plugins/code-quality-mentor/
  commands/scan.md                # slash-command shim that invokes the skill
  skills/scan/
    SKILL.md                      # the workflow Claude follows
    scripts/                      # executable code (bash + jq + awk helpers)
      find_repo_root.sh
      check_prereqs.sh
      detect_languages.sh
      run_pmd.sh
      merge_reports.sh            # combine PMD and LLM-scan findings
      blame_warnings.sh
      update_catalog.sh           # maintainer-only catalog tooling
      lint_markdown.py            # Markdown linter wrapping vendored PyMarkdown
      lint_markdown.yaml          # linter policy
      _vendor/                    # vendored PyMarkdown + pure-Python deps
      licenses_manual/            # third-party license attributions
      tests/                      # bats-core test suite + lint smoke test
    references/                   # documentation Claude reads on demand
      llm_scan_prompt.md          # prompt template for the LLM antipattern scan
      slop-checks.md              # in-skill carve-out applied to LEARNING_PLAN.md
    assets/                       # static data files
      pmd-languages.json          # Linguist language name -> PMD ruleset map
      antipatterns.json           # curated catalog driving the LLM scan
      antipatterns.schema.json    # JSON Schema for the catalog
docs/CATALOG.md                   # maintainer guide for the catalog
CHANGELOG.md                      # release notes per version
```

## Tests

```text
plugins/code-quality-mentor/skills/scan/scripts/tests/run.sh
```

The suite is organized in three layers:

- **Layer 1** (needs only `bats` + `jq`): script logic tests for `detect_languages.sh`, `merge_reports.sh`, `update_catalog.sh`, schema validation of `pmd-languages.json`, and structural checks against `antipatterns.json`.
- **Layer 2** (needs `git`): `find_repo_root.sh`, `check_prereqs.sh`, and `blame_warnings.sh` against a real synthetic repo.
- **Layer 3** (needs `java`, `javac`, `pmd`, and a Linguist implementation): end-to-end smoke test through the PMD + LLM-scan (stubbed) pipeline.

Tests that need a tool not on PATH skip themselves with a notice. The CI workflow under `.github/workflows/test.yml` exercises layers 1+2 in one job and all three layers in a second job.

A separate Python smoke test at `plugins/code-quality-mentor/skills/scan/scripts/tests/run_lint_smoke.py` covers the Markdown linter wrapper (`lint_markdown.py`): it exercises the vendored PyMarkdown tree, the pre-pass checks for issues PyMarkdown silently accepts, the `LEARNING_PLAN.md` schema check, and `--fix` mode end-to-end. Run it locally with `python3 plugins/code-quality-mentor/skills/scan/scripts/tests/run_lint_smoke.py`.

## License

First-party content is MIT-licensed. See [LICENSE](LICENSE).

Third-party software bundled under `plugins/code-quality-mentor/skills/scan/scripts/_vendor/` is distributed verbatim under its own licenses (MIT, BSD-3-Clause, Apache-2.0, PSF-2.0). See [`plugins/code-quality-mentor/skills/scan/scripts/_vendor/NOTICE`](plugins/code-quality-mentor/skills/scan/scripts/_vendor/NOTICE) for per-package attribution and full license texts.
