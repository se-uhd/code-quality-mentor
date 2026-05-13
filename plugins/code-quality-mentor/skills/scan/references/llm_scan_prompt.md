# LLM antipattern scan — prompt template

This file is loaded by the `scan` skill at the "Run the LLM antipattern scan" step. The skill reads it together with `assets/antipatterns.json` and applies the instructions below to the user's repository. The output is a JSON file in the same shape PMD produces, so the rest of the pipeline (`merge_reports.sh`, `blame_warnings.sh`, LEARNING_PLAN.md synthesis) consumes it without changes.

## Inputs you have

- `CATALOG`: the parsed contents of `assets/antipatterns.json` (sources + entries).
- `PMD_REPORT`: the parsed contents of `.code-quality-mentor/pmd-report.json`.
- `SELECTED_LANGUAGES`: the PMD language IDs the user agreed to scan (from the earlier language-confirmation step).
- `REPO_ROOT`: the absolute path of the repository being scanned.

## What to do

1. **Pick the file set.**
   - Start with the union of:
     - every file that appears in `PMD_REPORT.files[].filename`, and
     - the top 20 source files (by SLOC) in `SELECTED_LANGUAGES` under `REPO_ROOT`, discovered via `git ls-files | xargs wc -l` and filtered by extension.
   - Cap the total set at **100 files**. If the cap binds, prefer the PMD-flagged files first, then the largest-by-SLOC.
   - Skip vendored / generated paths the user's `.gitattributes` marks as such.

2. **Scan each file.**
   - Use the `Read` tool to load the file contents. Stream in chunks if the file is large; you do not need to read past the first 2000 lines unless the file is one cohesive method/class.
   - For each catalog entry, check whether the file matches its `llm_detection_signals`.
     - **Prefer precision over recall.** Flag only when **at least two signals match**, OR when one structurally strong signal does (e.g., a single method > 100 lines for `long_method`).
     - When the catalog entry has `language_notes` for the file's language, apply them — including any explicit "not this smell" carve-outs (e.g., Kotlin sealed-class `when` is not `switch_statements`).
   - **De-duplicate against PMD.** If a catalog entry has a `pmd_overlap` rule and that rule already appears in `PMD_REPORT` for the same `filename`, skip the LLM finding for that file. PMD's deterministic detection wins.

3. **Emit each finding.** A finding is a violation object in PMD-shape:
   ```json
   {
     "beginline": <int — first line of the offending construct>,
     "endline":   <int — last line, or beginline if a single line>,
     "rule":      "<catalog entry id, e.g., 'long_method'>",
     "ruleset":   "<catalog entry family, e.g., 'Bloaters'>",
     "description": "<one sentence explaining specifically why this code matches — name the signals you saw>",
     "priority": 3,
     "externalInfoUrl": "<first canonical_references[].url for the entry, or empty string>"
   }
   ```
   The `description` is the most important field: it must cite the **specific signals** you saw in this code, not the catalog's generic description. The user reads it as the reason this line was flagged.

4. **Assemble the report.** Group findings by filename. Build:
   ```json
   {
     "formatVersion": 0,
     "pmdVersion": "llm-scan-<CATALOG.version>",
     "files": [
       {
         "filename": "<absolute path under REPO_ROOT>",
         "violations": [ <findings for this file> ]
       },
       ...
     ]
   }
   ```
   If you found nothing, still emit the wrapper with an empty `files` array.

5. **Write the file.** Use the `Write` tool to write the assembled JSON to:
   ```
   <REPO_ROOT>/.code-quality-mentor/llm-scan-report.json
   ```
   Report the path back to the calling skill so it can hand it to `merge_reports.sh`.

## Hard constraints

- **Never fabricate code locations.** Every `(filename, beginline, endline)` triple must point at lines you actually read. If you cannot confidently localize a finding, drop it.
- **Never invent catalog rule ids.** Only use ids that appear in `CATALOG.entries[].id`. If you spot a smell with no catalog entry, do not flag it — note it separately to suggest as a catalog addition.
- **Stay within the precision-over-recall posture.** Three high-precision findings per file is plenty; ten low-precision findings is noise.
- **Respect `pmd_overlap`.** A finding suppressed by PMD overlap is still a real smell — it just does not need to be repeated by the LLM scan.
- **Use only the canonical reference URLs in the catalog.** Do not fabricate `externalInfoUrl` values.
