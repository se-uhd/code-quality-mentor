# Slop checks

This file is the carve-out the `scan` skill applies as a post-pass to a freshly written `LEARNING_PLAN.md`. It is intentionally small. Most paper-prose tropes do not apply to a coaching artifact, and a long catalog is a long catalog to enforce.

**Cap:** ~15 entries. If the list grows past that, prune before extending. Focused beats comprehensive.

**Each entry has:**

- a short id used as a `## <id>` heading,
- a one-line **Rule** stating the obligation,
- **Bad** examples drawn from real generated plans (the field-tested negatives),
- **Good** rewrites the carve-out asks for.

---

## anti-copula

**Rule:** Use plain "is" or "shows". Do not replace the copula with "serves as", "marks", "represents", "is the diagnostic", "is the load-bearing signal", "is the trigger", or similar promoted verbs.

**Bad:**

- "the 10-line comment is the diagnostic"
- "the second switch is the load-bearing signal"
- "every read becomes a guess about who wrote it last"
- "every write becomes an invisible influence on a distant reader"

**Good:**

- "the 10-line comment shows the coupling"
- "two switches over the same discriminator is enough"
- "every reader has to guess which closure last wrote the var"
- "every write affects readers elsewhere"

---

## invented-concept-labels

**Rule:** Do not coin compound nouns of the form `<domain noun> + (creep | trap | paradox | drift | inversion | vacuum)`. Use existing terminology when one exists; otherwise describe what is happening in plain words.

**Bad:**

- "orchestration creeps"
- "duplication ossifies"
- "workload creep"

**Good:**

- "the function grew until it stopped fitting on one screen"
- "the duplicates drifted and now have different error messages"
- "the workload kept growing without anyone noticing"

---

## em-dash-budget

**Rule:** At most 1 em-dash per ~200 words of prose, counting only em-dashes outside fenced code blocks. The plan is short and code-heavy; the looser paper-prose budget does not apply. When the count is over, prefer comma, semicolon, or a sentence break.

**Bad (over budget):** a plan with 22 em-dashes in 2122 words (1 per ~96 words).

**Good (within budget):** a plan with 8 em-dashes in 2000 words (1 per ~250 words), used only where the sentence is genuinely parenthetical.

---

## no-anthropomorphizing

**Rule:** Variables do not "want", classes are not "asking for", methods do not "tell a story". Describe what the code does, not what it would say if it could speak.

**Bad:**

- "the variable is asking for an owning object"
- "the discriminator wants to become a class"
- "the method tells a story by itself"

**Good:**

- "the variable should be owned by a small object with named transitions"
- "the discriminator should be replaced by the polymorphic type that already exists"
- "the method does several things and the name only describes one of them"

---

## grounded-references

**Rule:** Every Further reading entry has a 2–4 sentence paraphrase that says what is in the reference. Label paraphrases as paraphrases; do not assert verbatim quotes that have not been verified. Banned annotations: "the canonical treatment", "deliberately so", "the exact remedy", "the canonical reference".

**Bad:**

- "Martin Fowler, *Refactoring* ch. 3 'Duplicated Code'. The opening smell of the chapter, deliberately so."
- "The canonical treatment, including when Extract Method *isn't* the right call."

**Good:**

- "Martin Fowler, *Refactoring* ch. 3 'Duplicated Code' (p. 73). Fowler's argument, paraphrased: he opens the chapter with this smell because consolidating duplicates is often the prerequisite for naming the abstraction underneath. The remedy depends on shape: *Extract Function* for same-class fragments, *Pull Up Method* for sibling classes."

---

## no-editorial-subtitles

**Rule:** The `## <rule_id>` heading is the rule id, nothing else. No conceptual subtitle, no "—" suffix on the heading line.

**Bad:**

- "## long_method — orchestration creeps until the method tells a story by itself"
- "## shared_mutable_state — two closures coordinating through a `var` they don't own"

**Good:**

- "## long_method"
- "## shared_mutable_state"

---

## no-bold-first-paragraph-leads

**Rule:** Prose subsections (Concept, Why it matters here, Refactoring, Evidence, Further reading) are plain markdown. The only bold-field syntax permitted is in the metadata block (`**Family:**`, `**Source:**`, `**Occurrences:**`, `**Locations:**`) and at the start of a Further reading entry where bold marks the citation.

**Bad:**

- "**What this is really about.** A function should let a reader hold its intent in one pass."
- "**Why it matters.** Long entry points accumulate cross-cutting state."

**Good:** place the content under the `### Why it matters here` heading; the prose body has no bold lead.

---

## proper-markdown-links

**Rule:** Every URL is wrapped in `[title](url)`. Never write a raw URL, a bolded URL (`**https://...**`), or angle-bracket links (`<https://...>`). When a URL supplements a citation (for example, a conference talk's video), wrap it as `[video, ~30 min](url)`, not as a trailing bare URL.

**Bad:**

- "- **https://refactoring.guru/smells/duplicate-code** — quick lookup"
- "Rich Hickey, *The Value of Values*, StrangeLoop 2012, https://www.infoq.com/presentations/Value-Values/ (~30 min)."

**Good:**

- "- [refactoring.guru: Duplicate Code](https://refactoring.guru/smells/duplicate-code) — quick lookup"
- "Rich Hickey, *The Value of Values*, StrangeLoop 2012 ([video, ~30 min](https://www.infoq.com/presentations/Value-Values/))."
