# First-Principles Analysis

**Status: applies to any deep documentation artifact, in any language or domain.**

When asked to analyze code, audit specs, write a design document, or describe any non-trivial system, default to **first-principles depth**: explain the system as if the reader has zero prior context. Assume they don't know the language, the libraries, the domain, the regulation, or the file formats. Build everything up from the ground.

This rule applies to:
- Code analysis docs (e.g. "analyze this library's code", "describe what this library does")
- Design docs (new feature, new subsystem, migration plan)
- Postmortems
- Architecture overviews
- Any "explain it to me" / "describe in plain English" / "go deeper" request

Quick reference answers and inline comments are exempt. This rule kicks in once the artifact lives in `docs/`, `docs/design/`, or any repo-tracked file a reader expects to come back to.

## Core principle

If a competent engineer who has never touched this codebase before would still have unanswered questions after reading the doc, the doc is not done. **Depth, not breadth, is the deliverable.**

Specifically, the doc must let the reader:
1. Understand *why* the system exists (domain, regulation, business driver).
2. Understand *what* each piece does without referring to the source code.
3. Trace a concrete piece of data end-to-end through the system.
4. Reimplement the system in a different language using only the doc as reference.

If any of those four are not achievable, the doc has not gone deep enough.

## What "first-principles" means here

### 1. No assumed context

Don't write "uses a schema-validation library" without explaining what that library is, why it matters, and what behavior it enforces. Don't write "a connection pool" without explaining what a connection pool is and why pooling matters. Don't write "per the 2025 reporting regulation" without explaining what that regulation actually requires.

Rule of thumb: if a reader who's never seen this language/library/domain would have to look a term up, expand it inline (or in a Prerequisites section) instead of forcing the lookup.

### 2. Prerequisites section up front

Every first-principles doc has a Prerequisites section covering the technical primitives the rest of the doc relies on:

- The programming language(s) involved (key idioms a reader of another language wouldn't recognize).
- The protocols (HTTP, gRPC, whatever).
- The file formats (CSV, XML, JSON, ZIP, columnar formats).
- The libraries (what they are, what they do, why they were chosen).
- The data model (databases, schemas, key invariants).
- The domain (regulation, market, business logic).
- The glossary (any non-English or jargon terms used in the source).

The Prerequisites section is allowed to feel "long", that's the point. A reader can skip it if they already know the material; a newcomer cannot recover the missing context any other way.

### 3. Worked examples with concrete values

Every algorithm, every transformation, every parser must be walked through with **real input and real output**. Not pseudocode, not "assume some CSV". Pick one specific row, one specific URL, one specific filename, and trace it through.

Example: when describing a number-parsing routine, don't just say "handles thousands separators". Show:
- Input: `"1,234.56"` → Output: `1234.56` (comma is the thousands separator)
- Input: `"1.234,56"` → Output: `1234.56` (period is the thousands separator)
- Input: `",99"` → Output: `0.99` (missing leading zero)
- Input: `""` with the value required → raises a validation error

A reader who sees worked examples can predict edge cases. A reader who only sees the rule cannot.

### 4. Why-each-design-choice rationale

For every non-obvious design decision in the source code, the doc must explain *why* the author chose it. If the code uses a fixed-precision decimal type instead of a binary float, say why (precision for currency). If a crawler is synchronous instead of async, say why (latency-dominated, simplicity wins). If a remote endpoint's TLS verification is disabled, say why (broken cert chain) and link the file.

Where the source code is genuinely silent on rationale (and you can't reconstruct it), say so explicitly: "the code doesn't justify this choice; the apparent reasoning is X but treat this as a guess." Better an honest guess than a false certainty.

### 5. Failure modes catalogue

Don't just describe the happy path. For each subsystem, list every realistic failure (network error, schema change, encoding ambiguity, race condition, malformed input) and the system's response. A reader who only knows the happy path will be surprised by every real-world incident.

### 6. End-to-end worked example

The doc must have an appendix walking **one concrete unit of data** from input to output, through every component. For a crawler: one product row from the source website to the consumer's API response. For an auth system: one login attempt from credentials to issued token. For a deployment pipeline: one commit from push to running container.

This is the integration test in narrative form. It surfaces gaps that per-component descriptions miss.

### 7. Reimplementation roadmap

Every first-principles doc closes with a section titled "Reimplementation roadmap" or equivalent: an ordered list of how someone would port the system to a different language, with library equivalents, phase ordering, time estimates, and a callout of the *hard parts* (the 2-3 things a naive port would get wrong).

This serves two purposes:
- It forces you to confirm you actually understand the system (you can't port what you don't understand).
- It gives the reader a sanity check on whether the doc is sufficient.

## Length expectations

A first-principles doc for a non-trivial system is typically **3000+ lines**. If your "deep dive" of a 5000-line codebase is under 1000 lines, you almost certainly skipped prerequisites, glossed over algorithms, or omitted worked examples.

Length is not the goal. Comprehensiveness is. But systems of meaningful size produce docs of meaningful length, and tight prose still totals to thousands of lines once every algorithm has its worked example and every component has its quirks listed.

When in doubt, more depth. The reader can skim; they can't conjure missing detail.

## Anti-patterns

These are the patterns that make a first-principles doc fail:

- **Bullet-summary instead of prose.** "Uses HTTP, parses CSV, writes to DB." Tells nothing. Expand each bullet into a section.
- **Code without explanation.** Pasting a function and saying "this parses prices" is not analysis. Walk the algorithm. Explain the heuristics. Show inputs and outputs.
- **Pattern lists without per-instance detail.** "There are 8 patterns across 30 sources" is fine as scaffolding, but the doc still needs to walk each source individually, because the patterns hide per-source quirks (the broken TLS cert, the WAF block, the off-by-one date convention).
- **Skipping the boring parts.** The "trivial" CSV writer is exactly where a reimplementer trips up if they don't know the line-ending gotcha or the column-order convention. Document the trivial parts.
- **Assuming domain knowledge.** "Per the 2025 reporting regulation" without explaining the regulation. "EAN barcode" without explaining what an EAN is. "Connection pool" without explaining what pooling is.

## Measurement discipline (claims must be reproducible)

Every numeric or factual claim in a first-principles doc is a **claim**, not soft prose. A claim without a command behind it is fabrication, no matter how reasonable it reads. The reader cannot tell the difference between a measured number and a plausible-looking guess; the author has to.

### The five categories of claim

Every numeric or factual statement must fall into exactly one of these. Tag each in-doc (footnote-style or inline) so the reader can audit:

- **MEASURED**: produced by a deterministic command run against data on disk. Record `(command, value, source-path, measured-on)`.
- **DERIVED**: arithmetic on other MEASURED values. Record `(formula, inputs, result)`.
- **RANGED**: summarises N≥5 MEASURED observations across distinct snapshots, chains, or instances. Record `(N, snapshots-or-instances, min, median, max, command-used)`.
- **STRUCTURAL**: a fact about code shape (line numbers, function names, control flow). Record `(file, line-range, exact-snippet, verified-on)`.
- **DOCUMENTED**: claim from an external authoritative document (vendor spec, RFC, language reference, upstream README). Record `(source-url-or-path, exact-quote)`.

Anything outside these five is **FORBIDDEN**. Remove it, do not weaken it.

### Forbidden softeners

These signal that a number was invented and is being hedged into defensibility:

- "Typically", "usually", "on average", "most chains" without a RANGED tag.
- "Approximately", "roughly", "~" prefixing a number with no MEASURED or RANGED source.
- "Tens of millions", "a few hundred", "around N", "on the order of", and other order-of-magnitude hedges, unless N is the actual measurement and the hedge is dropped.
- "Industry rule of thumb", "in general", "typically compresses ~Nx", any rule-of-thumb size or ratio.
- **Round numbers** (100, 500, 700, 50000, 100MB, 1GB) in empirical claims. Round numbers are a red flag for invention; measurements produce specific digits. If a measurement happens to land on a round value, cite the command anyway.
- Mixed unit bases. Decide `MB = 10^6 bytes` and `MiB = 2^20 bytes` at the top of the doc and never mix.

### The reach-for rule

When the next character to type is a digit, the very next action is **not** finishing the sentence. The next action is:

- Reach for the data directory, not the keyboard. (`wc -l`, `du`, `find`, `ls | wc -l`.)
- Reach for the source file, not the prose describing it. (`grep`, `sed`, line numbers verified.)
- Reach for a second snapshot, not an adjective. (RANGED claims need N≥5.)
- Reach for an actual test, not folklore. ("CSV compresses Nx" requires running `zip` on the real data, not a remembered ratio.)

The doc is a presentation layer. The truth is in the data and the source. The doc must render that truth, not paraphrase it.

### The forbidden moves (named failure modes)

These are the patterns that cause iterative-audit loops:

- **Re-stating a doc number without re-measuring.** If the doc says "188 stores" and you are auditing it, run `wc -l` again. Do not trust prior prose.
- **Citing a single snapshot to support a "typical" claim.** RANGED requires N≥5.
- **Rounding to soften a measurement.** If the count is 21,657, do not round to "about 22,000."
- **Substituting plausibility for measurement.** "CSV typically compresses 8-10x" is forbidden. Run `zip -9` and record this data's actual ratio.
- **Widening the claim to be technically defensible.** "Around 10 million rows" is not better than "10,190,298"; it is worse. Specificity is mandatory.
- **Carrying old prose forward across rewrites.** If a section is rewritten, every empirical claim in the new section is re-measured. Do not assume a prior measurement still applies in the new framing.
- **Marking findings "low priority" or "stylistic."** Findings are fixed or the claim is removed.

### Reference protocol

For any doc with non-trivial empirical content, follow a four-phase verification protocol: Phase 1 inventory of empirical claims; Phase 2 a `measure.sh` script producing a `measurements.json`; Phase 3 in-doc tagging and lint; Phase 4 a three-orthogonal-auditor cycle (data / code / form). Stop condition: two consecutive clean runs of each auditor, lint at zero, and the measurement script stable.

The point of the protocol is structural prevention over reactive auditing: a claim that cannot be produced by a command cannot enter the doc in the first place. Iterative auditing catches fabricated numbers after the fact; the protocol stops them at the door.

## Standard structure

A first-principles analysis doc typically has these sections, in order:

1. **Background.** Why this system exists. The domain. The regulation or business driver. The system at one glance (architectural diagram with concrete data flow).
2. **Prerequisites.** Every technical primitive the rest of the doc relies on, explained from scratch.
3. **Project shape.** Directory layout. Dependencies (with what each library does and why). Build/run commands.
4. **Subsystem-by-subsystem deep dives.** For each major component: every public method, every algorithm walked through with worked examples, every quirk documented.
5. **Per-instance detail.** Where the system has N instances of a pattern (30 sources, 10 importers, etc.), walk each one individually.
6. **Operational concerns.** Deployment, scheduling, monitoring, failure modes.
7. **Shortcuts and known issues.** Where the code is intentionally less rigorous than it could be, and why.
8. **Reimplementation roadmap.** Ordered phases, library equivalents, time estimates, hard parts.
9. **Worked end-to-end example.** One concrete unit of data traced through every component.
10. **Failure modes catalogue.** Every realistic failure and the system's response, in table form.
11. **Glossary.** Every non-English or jargon term used anywhere in the source or the doc.
12. **License / provenance.** Where the source lives, what license, what's been modified.

Not every doc needs every section. Pick the ones that fit. But sections 1, 2, 4, 7, 9, and 11 are mandatory.

## When this rule kicks in

Cues that imply first-principles depth:
- "explain in plain English"
- "describe in detail"
- "go deeper" / "much more detail"
- "as if you had to implement it in another language"
- "as if you had to explain it to someone with no context"
- "comprehensive analysis"
- "be thorough"
- "be immaculate"
- "design doc"
- "architecture overview"
- "postmortem"

Cues that do NOT imply first-principles depth (lighter touch is fine):
- "summarize"
- "what does this do?"
- "quick overview"
- "tldr"

When in doubt, default to first-principles. Lighter docs are easy to retro-fit; sparse docs are not.

## Companion rules

- `writing-plans.md`: for multi-step implementation plans (the doc that follows the design doc).
- `brainstorming.md`: the design gate that happens BEFORE writing a design doc.
- `proof-discipline.md`: how to frame and label a correctness claim; its `sampled` / measured labels inherit this rule's MEASURED / DERIVED / RANGED / STRUCTURAL / DOCUMENTED taxonomy.

## Why this exists

The reader of a deep doc cannot tell a measured number from a confident guess, and a plausible-sounding figure written without measurement is indistinguishable from a true one until someone audits it. Depth without measurement discipline produces docs that read authoritatively and mislead silently. The depth-target makes the doc complete; the measurement discipline makes it trustworthy. Together they let a newcomer both understand the system and rely on every number in the description.
