---
description: Scan the current git repository with PMD, attribute each warning to a git-blame author, let the user pick one developer, and write a tailored LEARNING_PLAN.md for them.
---

Use the `code-quality-mentor:scan` skill.

The skill's full workflow lives in `skills/scan/SKILL.md`. By default it operates on the current working directory's enclosing git repository. The skill is interactive: it asks the user to confirm which languages to scan (when multiple are detected), pick one author from the list of committers whose lines triggered PMD warnings, and supply tailoring preferences (depth, focus area, seniority framing).

The skill writes two intermediate JSON files under `<repo>/.code-quality-mentor/` (`pmd-report.json`, `blame-report.json`) and one final artifact at the repo root: `LEARNING_PLAN.md`. Existing files at those paths are overwritten on each run. The user's source code is not modified.
