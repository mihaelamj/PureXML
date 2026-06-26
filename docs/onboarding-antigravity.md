# Onboarding: working on PureXML in Google Antigravity (Gemini)

This document is written for an AI agent (Gemini) operating inside Google
Antigravity. It is deliberately literal and exhaustive. **Do exactly what it
says, in the order it says.** When a step says "run X", run X and read its
output before continuing. Do not skip the verification steps. Do not infer; when
this document gives a command or a rule, follow it verbatim.

Antigravity auto-loads `GEMINI.md` (repo root) and `AGENTS.md` as always-on
rules. This file is the long-form companion: `GEMINI.md` is the short
constitution, this file is the full procedure. Read both before your first
change.

---

## 0. The one thing that matters most

PureXML is an XML/XSD validator. Its single most important quality is:

> **Never reject a valid schema or a valid document.**

In the conformance numbers (Section 5) this is the bucket
`valid-schemas-rejected`. It is currently **0** and must **never go up**. A
change that fixes ten bad schemas but wrongly rejects one good schema is a
**failure** and must not be merged. When in doubt, do less: it is always
acceptable to *miss* an invalid schema (under-reject); it is never acceptable to
reject a valid one (over-reject). This asymmetry drives every decision below.

---

## 1. What PureXML is

- A **pure-Swift** XML parser, emitter, and **XSD 1.0 schema validator**, with
  XPath/XSLT support. It is a standalone Swift package (root `Package.swift`),
  not part of a larger workspace.
- It compiles a `<xs:schema>` document into an internal model and then validates
  XML instances against it.
- The active work is **schema-validity conformance**: making the validator
  correctly *reject* invalid schemas (and accept valid ones), measured against
  the W3C XML Schema Test Suite (XSTS).

### Non-negotiable constraints (these are hard rules, never violate them)

1. **No external SwiftPM dependencies.** Do not add a package dependency. Ever.
2. **No C, C++, Objective-C, JavaScript, or any generated parser runtime** in the
   package. Pure Swift only.
3. **Public API lives under the `PureXML` namespace tree.** Do not add public
   symbols outside it.
4. **Must build on macOS, Linux, and WASI.** Do not use APIs unavailable on
   Linux/WASI. Foundation is allowed only for file access in tests.
5. **Clean-room only.** There are reference implementations (Xerces, libxml2,
   .NET, Python `xmlschema`) under a separate research repo. You may **read them
   to understand a rule**, but you must **never copy their code**. Re-derive in
   Swift.
6. **Tests may import only** `Foundation`, `Testing`, and `@testable import
   PureXML`. Never `import PureXML` (use `@testable`). Never import anything else
   in a test.

---

## 2. Repository layout (where things are)

- `Sources/Schema/`, the XSD schema engine. **Almost all your work is here.**
- `Sources/` (other folders), the XML parser, emitter, XPath, XSLT, regex.
- `Tests/`, Swift Testing test suites. One file per topic.
- `Tests/XSTSSuiteTests.swift`, the opt-in conformance runner (Section 5).
- `docs/`, rules and design docs. **Read these:**
  - `docs/production-readiness.md`, the bar for shipping. Read it every time.
  - `docs/schema-validity-burndown.md`, the conformance plan, priority order,
    and the per-change protocol. **This is your playbook.**
  - `docs/rules/code-style.md`, `namespacing.md`, `cross-platform.md`,
    `testing.md`, `verification.md`, `research-first.md`, coding rules.
  - `docs/xsts-deviations.md`, documented, intentional deviations (do not
    "fix" these; they are spec ambiguities).
- `CHANGELOG.md`, every shippable change gets an entry here.
- `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, agent instruction files (read first).

---

## 3. Environment and tools

You need these on the machine (they are already installed in the normal dev
environment):

- `swift` (Swift 6.1+ toolchain).
- `swiftformat` and `swiftlint` (formatting/lint gates).
- The XSTS corpus, unpacked at: **`/private/tmp/xsts/xmlschema2006-11-06`**.
  This path is the value of the `XSTS_ROOT` environment variable used by the
  conformance runner. If it is missing, the conformance runner silently does
  nothing (it is opt-in), so confirm the directory exists before relying on it:
  `ls /private/tmp/xsts/xmlschema2006-11-06/suite.xml`. To obtain it, run
  `bash scripts/fetch-xsts.sh`, which downloads and SHA-256-verifies the official
  W3C archive into that path (the suite is never vendored).

---

## 4. The commands (run these, in this order, for every change)

These are the project's gates. A change is not done until **all** pass.

```sh
# 1. Build.
swift build

# 2. Format check, then lint (strict). Fix any violation before continuing.
swiftformat . --config .swiftformat --lint
swiftlint --config .swiftlint.yml --strict

# 3. Project style/namespacing checks.
bash scripts/check-style.sh
bash scripts/check-namespacing.sh

# 4. Full unit test suite (fast; excludes the opt-in XSTS runner).
swift test

# 5. WASI build check (cross-platform gate).
bash scripts/check-wasm.sh

# 6. The conformance differential (opt-in; ~13 seconds in release).
XSTS_ROOT=/private/tmp/xsts/xmlschema2006-11-06 swift test -c release --filter XSTS
```

If `swiftformat --lint` reports a file needs formatting, run
`swiftformat . --config .swiftformat` (no `--lint`) to fix it, then re-run the
lint. **Always format new files before committing**, the pre-push hook will
otherwise reject the push.

---

## 5. The conformance campaign (what success is measured by)

The W3C XSTS runner (`Tests/XSTSSuiteTests.swift`) runs the entire suite and
counts four buckets. The expected counts are **pinned** as constants near the
top of that file:

| Constant | Meaning | Current value | Direction |
|---|---|---|---|
| `knownSchemaValidRejected`   | valid schemas we wrongly **reject**   | **0**  | must NEVER rise; hold at 0 |
| `knownSchemaInvalidAccepted` | invalid schemas we wrongly **accept** | **43** | drive DOWN |
| `knownInstanceValidRejected` | valid instances we wrongly **reject** | **0**  | must not rise; hold at 0 |
| `knownInstanceInvalidAccepted`| invalid instances we wrongly accept  | **31** | drive down |

The runner asserts these counts **exactly**. So:

- When your change correctly rejects N more invalid schemas, the actual
  `schemaInvalidAccepted` drops by N and the test "fails" reporting the new
  lower number. That is success, **update the pinned constant to the new
  number**.
- If **any** bucket goes UP, that is a regression. **Stop. Revert or fix.** A
  rise in `schemaValidRejected` or `instanceValidRejected` (a false positive) is
  the worst case and is never acceptable.

The per-case failures are written to **`/tmp/xsts-failures.txt`** after each
run, one line per disagreement, e.g. `name00504m2: invalid schema accepted`. Use
this file to find and classify work (Section 7).

> **Caution:** `/tmp/xsts-failures.txt` is written only *after* the run
> completes. If the run crashes, the file is **stale**. Always check the exit
> code and the printed bucket line, not just the file.

The production bar (read `docs/production-readiness.md`): all four buckets to 0
in both directions; false positives (valid rejected) are the worst stopper;
disclosed under-rejection is acceptable debt, hidden debt is a violation.

---

## 6. The per-change procedure (the "PR-critic-loop"), follow every step

Do **one** schema-validity rule per change. For each one:

1. **Measure first.** Look at `/tmp/xsts-failures.txt`. Pick a family of related
   failing cases (Section 7). **Read the actual `.xsd` files** of several cases
   in that family before writing any code, do not assume what rule they need.
   Confirm they all fail for the *same* reason.

2. **State the rule in one sentence**, citing the XSD 1.0 clause it enforces. If
   you are unsure of the spec, read `docs/rules/research-first.md` and consult
   the reference sources (study only, never copy).

3. **Implement at the compile-time consistency layer.** New schema-validity
   checks live in `Sources/Schema/` and return `[String]` (a list of error
   messages; empty = valid). They are wired into one of the aggregators (see
   Section 9). Keep the check **conservative**: only reject when you are certain
   the schema is invalid.

4. **Add unit tests** in a new `Tests/Schema*Tests.swift` file: at least one
   schema that must be **rejected** and several valid variants that must
   **compile**. Write the test file **before** running the conformance
   differential (see the race note in Section 8).

5. **Run all gates** (Section 4). Build, format, lint, unit tests must be green.

6. **Run the conformance differential** (Section 4, step 6). Confirm:
   `schemaInvalidAccepted` went DOWN, and **no other bucket went up** (this is a
   hard gate). If `schemaValidRejected` rose, you introduced a false positive ,
   find which valid schema you broke (diff `/tmp/xsts-failures.txt`), and fix or
   revert.

7. **Run an adversarial critic** (Section 6a). This is mandatory.

8. **Update the pinned baseline** constant in `Tests/XSTSSuiteTests.swift` to the
   new lower number. Re-run the conformance differential to confirm it now
   passes.

9. **Document.** Add a `CHANGELOG.md` entry (under `## [Unreleased]`, in the
   `### Fixed` or `### Added` section) describing the rule, the clause, the XSTS
   delta, and any disclosed under-rejection. Update the count in
   `docs/schema-validity-burndown.md`.

10. **Commit and merge** (Section 10).

### 6a. The adversarial critic (mandatory, do not skip)

Before merging, spawn a **separate** review pass whose *only job is to find a
valid schema your new check would wrongly reject.* Give it:

- the exact files you changed,
- the rule and the XSD clause,
- an instruction to **construct concrete valid `<xs:schema>` documents** that
  the new code would reject, build them, and run them against the compiler to
  confirm.

The critic must specifically probe the **namespace-conflation trap** (Section
8): does the rule confuse a built-in or imported type/element/attribute with a
same-local-name user one? If the critic finds a real false positive, **fix it
before merging** (usually by namespace-gating, Section 8). The XSTS suite does
**not** contain every adversarial case, so the critic catches false positives
the suite misses. This has happened repeatedly; it is the single highest-value
safety step.

---

## 7. How to pick the next task (measure-first)

```sh
# Group the current failing invalid-schema cases by name family:
grep 'invalid schema accepted' /tmp/xsts-failures.txt \
  | sed -E 's/[0-9].*//; s/_.*//; s/\/.*//' | sed -E 's/[0-9]+$//' \
  | sort | uniq -c | sort -rn | head -20
```

Then for a chosen family, list its cases and **read the schemas**:

```sh
grep 'invalid schema accepted' /tmp/xsts-failures.txt | grep -iE '^familyName'
# find and read a case's .xsd:
find /private/tmp/xsts/xmlschema2006-11-06 -iname 'caseName.xsd'
```

**Estimate yield before investing.** Some families are large but each case is a
different rule (e.g. `addB` one-offs) or needs a subproject (regex-engine
fidelity, cross-document composition). Prefer a family where many cases share
one clean, well-defined rule. A clean rule with low over-rejection risk and a
yield of even 2 is fine; a risky rule (could reject valid schemas) is not worth
it regardless of yield.

> **Watch out:** the same test-group name can appear in *different* testSets for
> *different* rules (the failures file does not disambiguate). If a case seems
> already handled, it may be a same-named case in another testSet. Verify by
> reading the actual schema and finding its testSet.

---

## 8. Recurring traps and their exact fixes

These have each bitten this project multiple times. Memorize them.

### Trap A, the namespace-conflation trap (has occurred 7+ times)

**Symptom:** a new rule resolves a type/element/attribute name by stripping the
prefix and matching the local name, and then wrongly rejects a valid schema
because a **built-in** (e.g. `xs:string`) or an **imported** component shares
that local name with a user component.

**Rule:** any check that resolves a schema name must **resolve its namespace**,
not just strip the prefix. Use
`PureXML.Schema.XSDNode.referenceNamespace(reference, bindings)` (where
`bindings = XSDNode.namespaceBindings(of: schema)`) and only act when it resolves
to the namespace you intend (usually the schema's own `targetNamespace`). A
reference resolving to the XSD namespace is a built-in and must be skipped.

When a rule depends on cross-document resolution and the schema has
`import`/`include`/`redefine`, the safest move is to **stand down entirely** for
that schema (gate on `!hasExternalReference(schema)`), which is a disclosed
under-rejection. Many existing checks do this.

### Trap B, swiftformat vs swiftlint brace conflict

**Symptom:** you write a multi-condition `if a, b, c {` (or `for ... where ... {`)
that is long; swiftformat moves the `{` to its own line; swiftlint then reports
an `opening_brace` violation. The two tools disagree and you cannot satisfy both
with that shape.

**Fix:** extract the condition into a `Bool`-returning helper so the `if` is a
single short expression with the brace on the same line:

```swift
if isNestedNamedDefinition(node, kind, parentIsTopLevel: parentIsTopLevel) {
    errors.append(...)
}
```

For `for ... where`, convert a long `where` into a `guard ... else { continue }`
inside the loop body so the `for` line stays short.

### Trap C, file/function size limits

swiftlint enforces: **file ≤ 400 lines**, **type body ≤ 250 lines**, **function
cyclomatic complexity ≤ 10**, **function parameters ≤ 5**, **line ≤ 180 chars**.
When you hit one:

- File too long → extract the new check into its **own new file**
  (`Sources/Schema/SchemaYourRule.swift`), `extension PureXML.Schema.XSDParser`.
- Complexity > 10 → split the function into smaller helpers.
- Params > 5 → bundle related arguments into one labeled tuple (≤ 2 members).
- A long `[String]` concatenation can time out the type-checker → break it into
  intermediate `let` bindings.

### Trap D, the test-write-before-differential race

If you launch the (release) conformance build/run and *then* create a new test
file, the release build may pick up a half-written file and fail with confusing
empty output. **Always write and save the new test file first**, run the fast
`swift test`, and only then launch the release XSTS differential.

### Trap E, reading schema attributes by local name

`XSDNode.attribute(node, "name")` matches by **local name only**. For a
schema-vocabulary attribute (`name`, `use`, `form`, `ref`, `default`, `fixed`,
…) read the **unprefixed** one (`attribute.name.prefix == nil`) so a foreign
`pre:name` is not mistaken for the real attribute. Skip foreign-namespace nodes
(`node.name?.namespaceURI == xsdNamespace`) and never descend into
`xs:appinfo` / `xs:documentation` (foreign content).

### Trap F, comparing values must be value-space, never lexical

When a rule compares two `default`/`fixed`/`enumeration` values (for example to
check that a restriction keeps a base attribute's fixed value), you must compare
them in the **value space of the type**, not as raw strings. Two lexically
different strings can be the **same value**: a list-typed value `"1   2  3"` and
`"1 2 3"` are both `[1, 2, 3]`; a `token` collapses whitespace; `"01"` and `"1"`
are the same integer. A string `==` over-rejects valid schemas (this caused a
real false positive: a list-of-int fixed value differing only in whitespace).
Also remember a `use="prohibited"` attribute is **removed** from the type's
attribute uses, so per-attribute clauses (fixed, required-equality) do not apply
to it. If you do not have a reliable value-space comparison for the type, **do
not enforce the value clause** (disclosed under-rejection) rather than risk a
false positive.

---

## 9. Where the checks live (file map)

Schema-validity checks are aggregated in two places, both in
`Sources/Schema/SchemaIDAttribute.swift`:

- **`consistencyErrors(schema, context, containers)`**, checks that run before
  the named types are compiled (structural / id / determinism / cycles /
  placement). Structural checks are gathered by `structureErrors(schema)` in
  `Sources/Schema/SchemaStructure.swift`.
- **`postNamedTypeErrors(schema, context, containers, derivation, typeMaps)`** ,
  checks that need the **compiled** types (`typeMaps.named` is the
  `[String: ElementType]` map): references, attribute-use uniqueness, value
  constraints against user types, substitution-member type derivation, all-group
  in extension.

To add a new check: write a `static func yourRuleErrors(...) -> [String]` in a
new file, then add `+ yourRuleErrors(...)` to the appropriate aggregator. Use
compiled types (`postNamedTypeErrors`) only if your rule needs resolved type
content; otherwise prefer the structural layer.

Representative existing checks to imitate (read these as templates):
`SchemaAttributeApplicability.swift` (per-node + top-level scans),
`SchemaNestedDefinition.swift` (recursive top-level/nested walk),
`SchemaSimpleTypeFinal.swift` (namespace-gated name map),
`SchemaExtensionAllGroup.swift` (compiled-type lookup),
`SchemaFacetApplicability.swift` (value/facet checks),
`XSDSimpleParser.swift` (`facetDefinitionErrors`).

---

## 10. Commit, branch, and release discipline (follow exactly)

- **Branch off `main`** for each change: `git checkout -b schema/your-rule-name`.
- Commit message format: `type(scope): summary`, e.g.
  `feat(schema): reject X (cos-rule-name)`. Body explains the rule, the clause,
  and the XSTS delta.
- **Never use an em dash** anywhere in commit messages, code, comments, or docs.
  Use a comma, period, colon, or rewrite the sentence.
- **Never add AI attribution** of any kind, no "Generated with", no
  "Co-Authored-By", no mention of Gemini/Antigravity/AI/assistant/"agent" in
  commit messages, PR descriptions, branch names, code comments, or any output
  that lands in the repo. All work must read as human-authored. (This document
  is the one exception, because it was explicitly requested as agent
  onboarding.)
- **Never `git push` to a GitLab remote.** Only GitHub remotes are allowed.
  Inspect the remote URL before pushing; if it contains `gitlab`, stop.
- Merge to `main` with a fast-forward only: `git checkout main && git merge
  --ff-only your-branch`, then `git push origin main`. Delete the branch.
- A pre-push hook runs `swift test` and a commit-message style check; if the
  push is rejected for formatting, format the offending file, amend, and push
  again.
- **Tagged releases:** bump `CHANGELOG.md` (move `## [Unreleased]` content under
  a new `## [x.y.z] - YYYY-MM-DD` header, add a fresh empty `[Unreleased]`),
  commit, then `git tag -a vX.Y.Z -m "..."`, `git push origin vX.Y.Z`, and
  `gh release create vX.Y.Z --title ... --notes ...`. The project is pre-1.0;
  stay on `0.x` until `docs/production-readiness.md`'s gates are met.

---

## 11. Current state (snapshot, post v0.2.0)

- Pinned baselines: **valid-schemas-rejected 0**, **invalid-schemas-accepted
  43**, **valid-instances-rejected 0**, **invalid-instances-accepted 31**.
  (These ratchet down as conformance work lands; always read the live constants
  in `Tests/XSTSSuiteTests.swift`.)
- The clean structural / applicability rule families are largely **done**:
  facet validity, structural content-model, UPA determinism, content order,
  identity-constraint XPath subset, wildcard namespace, final/block value space,
  simpleType content, circular derivation/references, attribute-use uniqueness,
  type-excludes-inline, ID value-constraint, all-group placement, element-ref
  namespaces, particle-restriction (MapAndSum etc.), substitution-member type,
  default/fixed exclusion, default/use, value-against-user-type, top-level and
  ref applicability, whiteSpace restriction direction, simpleType final
  list/union, all-group-in-extension, nested-named-definition, attribute-use
  restriction (required-relaxation half).
- **What remains (each is a deliberate subproject, not a one-line rule):**
  - **The fixed/default value-restriction clauses** (the most concrete next
    task): a restriction must keep a base attribute's (and element's) fixed
    value, compared in the type's **value space** (see Trap F, §8). This needs a
    value-space comparison helper (whitespace + list/union + lexical-to-value
    normalization). The required-relaxation half is already done in
    `SchemaAttributeRestriction.swift`; add the fixed clause there once you have a
    correct value comparison. Do NOT compare fixed values as raw strings.
  - **Regex-engine fidelity** (`RegexTest` family, ~22): make the pattern
    compiler correctly reject genuinely-invalid patterns *without* rejecting
    valid ones. **High over-rejection risk**, be very careful.
  - **Particle-restriction tail** (`particlesIk/L/Z/Hb/Ig`, ~40): needs the
    particle model enriched with more type information (NameAndTypeOK clauses
    nillable/fixed/block; Particle-Valid-Extension).
  - **Cross-document composition** (`attg`/`schZ`/`schN`, ~50): load and merge
    `import`/`include`/`redefine` so the existing rules run over the merged
    schema. This unlocks the largest remaining cluster.
  - **`addB`** (~19): adhoc one-offs, each its own investigation.
  - **Located diagnostics** (`#169`): line/column positions on every error (the
    IDE gate; a broad but mechanical refactor of the `[String]` error paths to
    carry `SourceRange`).

Pick from these only as deliberate, well-scoped efforts. Do not start one you
cannot finish cleanly. If you cannot find a clean, low-risk rule, say so rather
than forcing a risky change.

---

## 12. A worked example (one complete iteration)

The most recent change (`nested-named-definition`) is a model iteration:

1. Measured `/tmp/xsts-failures.txt`; saw `stA*` and `attgB*` families.
2. Read `stA008.xsd` (a `<simpleType name="foo">` nested inside a
   `<restriction>`) and `attgB002.xsd` (a `<attributeGroup name="abc">` nested
   inside another). Rule: a nested `simpleType`/`attributeGroup` may not be named
   (schema-for-schemas `localSimpleType` / nested `attributeGroup` is a ref).
3. Wrote `Sources/Schema/SchemaNestedDefinition.swift`: a recursive walk passing
   `parentIsTopLevel`, flagging a non-top-level XSD-namespace
   `simpleType`/`attributeGroup` with an unprefixed `name`; skipping
   appinfo/documentation. Wired into `structureErrors`.
4. Wrote `Tests/SchemaNestedDefinitionTests.swift` (reject nested-named; accept
   nested-anonymous, attributeGroup ref, top-level named).
5. Ran gates → green. Hit Trap B (brace conflict) → extracted a `Bool` helper.
6. Ran the differential → `invalid-schemas-accepted` 403 → 394, all other
   buckets held. Updated the pinned baseline to 394.
7. Ran the critic (17 constructed valid schemas) → zero false positives.
8. CHANGELOG entry, burndown count, commit on a branch, `--ff-only` merge, push.

Total: one clean, verified, reversible improvement, with the false-positive line
held at zero.

---

## 13. Definition of done (self-audit before you say "done")

- [ ] `swift build` succeeds.
- [ ] `swiftformat --lint` and `swiftlint --strict` report zero violations.
- [ ] `bash scripts/check-style.sh`, `check-namespacing.sh`, `check-wasm.sh` pass.
- [ ] `swift test` is fully green (all unit tests).
- [ ] The XSTS differential shows `invalid-schemas-accepted` down and **no other
      bucket up** (`valid-schemas-rejected` still 0).
- [ ] An adversarial critic found **zero** valid schemas your change rejects.
- [ ] New unit tests cover both a rejected case and several accepted cases.
- [ ] The pinned baseline in `Tests/XSTSSuiteTests.swift` matches the new count.
- [ ] `CHANGELOG.md` and `docs/schema-validity-burndown.md` updated.
- [ ] Commit message has the right format, no em dash, no AI attribution.
- [ ] Merged `--ff-only` to `main`; pushed to the GitHub remote (never GitLab).

If any box is unchecked, you are not done. Ask: "did I take the optimal path, or
one I hope no one inspects?" If you wrongly rejected even one valid schema, the
change is wrong no matter how many invalid ones it caught.
