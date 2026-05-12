# code-quality-mentor

A Claude Code plugin that turns PMD and SpotBugs warnings into a personalized learning plan for one developer on a team.

PMD already tells you *what* is wrong with the code, and SpotBugs adds bytecode-level bug detection on top for Java and Kotlin. `git blame` already tells you *who* wrote it. This plugin closes the loop: it picks one author, derives their characteristic code quality blind spots from the merged findings on their lines, and writes a tailored `LEARNING_PLAN.md` with concept explanations, refactor sketches of their actual code, and pointers to canonical references.

## What it does

The plugin provides one slash command:

```
/code-quality-mentor:scan
```

The workflow runs end to end on the enclosing git repository:

1. Detects which PMD-supported languages are present, using GitHub Linguist (or `enry`).
2. Runs `pmd check` with sensible default rulesets for each detected language.
3. If Java or Kotlin is present, asks whether to run SpotBugs against the existing compiled classes, rebuild first, or skip SpotBugs. When a Maven/Gradle/sbt build descriptor is detected, the rebuild option uses the project's own wrapper (`./mvnw`, `./gradlew`) when present. Existing classes are picked up from `target/classes`, `build/classes/java/main`, `build/classes/kotlin/main`, and similar standard locations.
4. Merges the PMD and SpotBugs findings into a single report (or uses the PMD report alone when SpotBugs did not run).
5. Attributes every warning's first line to a `git blame` author.
6. Asks you to pick one developer from the list, sorted by warning count.
7. Asks two or three tailoring questions: depth, focus area, and seniority framing.
8. Writes `LEARNING_PLAN.md` at the repo root: a 3-to-5-minute read covering the developer's top 3 to 5 rules, with refactor sketches drawn from their own flagged code.

Intermediate JSON reports live under `.code-quality-mentor/`. The plugin never modifies your source code.

## Supported languages

Every language for which PMD ships a rule-based ruleset (verified against [the PMD 7 rule reference](https://docs.pmd-code.org/latest/)):

Apex, HTML, Java, Java Server Pages, JavaScript, Kotlin, Maven POM, Modelica, PLSQL, Scala, Swift, Velocity Template Language, Visualforce, WSDL, XML, XSLT (the names match the Linguist language IDs used by `shared/pmd-languages.json`).

The plugin does not analyze languages that PMD parses for CPD (copy-paste detection) only — C/C++, C#, CSS, Dart, Fortran, Gherkin, Go, Groovy, Julia, Lua, Matlab, Objective-C, Perl, PHP, Python, Ruby, Rust, T-SQL, Coco. CPD finds duplication, not the rule-based warnings this plugin teaches from.

The language-to-ruleset map lives at `plugins/code-quality-mentor/shared/pmd-languages.json` and is straightforward to edit if you want a stricter or laxer default per language.

## Prerequisites

| Tool                    | Why                                              | Install (macOS)                   |
| ----------------------- | ------------------------------------------------ | --------------------------------- |
| `java` (>=11)           | PMD and SpotBugs runtime                         | `brew install temurin`            |
| `pmd` (>=7)             | Source-level static analyzer                     | `brew install pmd`                |
| `spotbugs` (>=4)        | Bytecode-level bug detector (Java/Kotlin)        | `brew install spotbugs`           |
| `jq`                    | JSON manipulation in the helper scripts          | `brew install jq`                 |
| `git`                   | Repository history and `git blame`               | `xcode-select --install`          |
| `github-linguist` *or* `enry` | Language detection in the repo             | `gem install github-linguist` *or* `brew install enry` |

Contributors who want to run the test suite also need `bats-core` (`brew install bats-core`).

The slash command calls `check_prereqs.sh` first and prints platform-specific install hints if anything is missing.

## Installation

In any Claude Code session:

```
/plugin marketplace add se-uhd/code-quality-mentor
/plugin install code-quality-mentor
```

`se-uhd/code-quality-mentor` is the GitHub shorthand for `https://github.com/se-uhd/code-quality-mentor`; the full HTTPS or SSH URL works equally well. To install from a local clone instead of GitHub, pass the path to the clone directory: `/plugin marketplace add /path/to/code-quality-mentor`.

## Updating

To pull the latest version of the marketplace and refresh the installed plugin:

```
/plugin marketplace update code-quality-mentor
```

This re-fetches the marketplace metadata from GitHub. After it completes, restart your Claude Code session (or run `/plugin install code-quality-mentor` again) so the updated plugin is picked up. To remove the plugin entirely: `/plugin uninstall code-quality-mentor`.

## Usage

`cd` into the Git repository you want to scan, then:

```
/code-quality-mentor:scan
```

Answer the prompts. When the run finishes, open `LEARNING_PLAN.md` at the repo root.

Add the scratch directory to your project's `.gitignore`:

```
.code-quality-mentor/
```

## Layout

```
plugins/code-quality-mentor/
  commands/scan.md            # slash-command shim that invokes the skill
  skills/scan/SKILL.md        # the workflow Claude follows
  scripts/                    # bash + jq + awk helpers
    find_repo_root.sh
    check_prereqs.sh
    detect_languages.sh
    run_pmd.sh
    find_classes.sh           # SpotBugs: locate compiled bytecode
    run_spotbugs.sh           # SpotBugs: run on bytecode, delegate parsing
    spotbugs_xml_to_pmd.sh    # SpotBugs: convert XML output to PMD-shape JSON
    merge_reports.sh          # combine PMD and SpotBugs findings
    blame_warnings.sh
    tests/                    # bats-core test suite (see below)
  shared/pmd-languages.json   # Linguist language name -> PMD ruleset map
```

## Tests

```
plugins/code-quality-mentor/scripts/tests/run.sh
```

The suite is organized in three layers:

- **Layer 1** (needs only `bats` + `jq`): script logic tests for `detect_languages.sh`, `find_classes.sh`, `merge_reports.sh`, and `spotbugs_xml_to_pmd.sh` (against a captured SpotBugs XML fixture), plus schema validation of `pmd-languages.json`.
- **Layer 2** (needs `git`): `find_repo_root.sh`, `check_prereqs.sh`, and `blame_warnings.sh` against a real synthetic repo.
- **Layer 3** (needs `java`, `javac`, `pmd`, `spotbugs`, and a Linguist implementation): end-to-end smoke test through the full PMD + SpotBugs pipeline.

Tests that need a tool not on PATH skip themselves with a notice. The CI workflow under `.github/workflows/test.yml` exercises layers 1+2 in one job and all three layers in a second job.

## License

MIT. See [LICENSE](LICENSE).
