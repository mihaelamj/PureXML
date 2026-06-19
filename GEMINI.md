# GEMINI.md, always-on rules for Antigravity agents in PureXML

These rules are always in effect. The full, step-by-step procedure is in
**`docs/onboarding-antigravity.md`**, read it before your first change. When a
rule here and a guideline elsewhere conflict, this file wins.

## The prime directive

PureXML is an XML/XSD validator. **Never reject a valid schema or a valid
document.** In the conformance counts this is `valid-schemas-rejected`; it is
**0** and must **never rise**. Under-rejecting (missing an invalid schema) is
acceptable; over-rejecting (rejecting a valid one) is a failure and must not be
merged. When unsure, do less.

## Hard constraints (never violate)

- No external SwiftPM dependencies. No C/C++/Objective-C/JavaScript/generated
  runtime. Pure Swift only.
- Public API stays under the `PureXML` namespace tree.
- Must build on macOS, Linux, and WASI.
- Reference implementations are for **reading only, never copying** (clean-room).
- Tests import only `Foundation`, `Testing`, and `@testable import PureXML`.

## Per-change procedure (do every step; details in the onboarding doc §6)

1. **Measure first**: read `/tmp/xsts-failures.txt`, pick a family, **read the
   actual `.xsd` files** before coding. Do one rule per change.
2. Implement conservatively in `Sources/Schema/`; return `[String]` errors; wire
   into an aggregator in `SchemaIDAttribute.swift`.
3. Add unit tests (one rejected case + several accepted cases). Write the test
   file **before** launching the release XSTS run.
4. Run all gates (build, `swiftformat --lint`, `swiftlint --strict`,
   `check-style.sh`, `check-namespacing.sh`, `swift test`, `check-wasm.sh`).
5. Run the conformance differential:
   `XSTS_ROOT=/private/tmp/xsts/xmlschema2006-11-06 swift test -c release --filter XSTS`.
   `invalid-schemas-accepted` must go DOWN and **no other bucket may rise**.
6. Run an **adversarial critic** that tries to construct a valid schema your
   change rejects. Fix any false positive before merging. (Mandatory.)
7. Update the pinned baseline in `Tests/XSTSSuiteTests.swift`, add a
   `CHANGELOG.md` entry, update `docs/schema-validity-burndown.md`.
8. Branch off `main`, commit, `git merge --ff-only`, push to GitHub.

## The traps that recur (onboarding doc §8)

- **Namespace conflation:** resolve a name's namespace with
  `XSDNode.referenceNamespace(ref, bindings)`; never just strip the prefix. A
  built-in (`xs:*`) or imported component must not be confused with a
  same-local-name user one. This has caused false positives 7+ times.
- **swiftformat vs swiftlint brace conflict:** extract a multi-condition `if`
  into a `Bool` helper; turn a long `for ... where` into `guard ... continue`.
- **Limits:** file ≤ 400 lines, type body ≤ 250, cyclomatic ≤ 10, params ≤ 5,
  line ≤ 180. Split into new files/helpers; bundle args into a labeled tuple.
- Read schema attributes **unprefixed** (`prefix == nil`); skip foreign-namespace
  nodes and `xs:appinfo`/`xs:documentation`.

## Commit discipline (never violate)

- Commit format: `type(scope): summary`. **No em dashes** anywhere.
- **No AI attribution** of any kind in commits, PRs, branches, code, or docs (no
  "Generated with", no "Co-Authored-By", no mention of Gemini/AI/agent). All work
  reads as human-authored. (`docs/onboarding-antigravity.md` is the sole
  exception, explicitly requested.)
- **Never push to a GitLab remote.** GitHub remotes only; check the URL first.
- Merge to `main` `--ff-only`. The pre-push hook runs `swift test` and a
  commit-message check.

## Definition of done

All gates green; conformance differential shows invalid-accepted down and **no
other bucket up** (valid-rejected still 0); the critic found zero false
positives; baseline/CHANGELOG/burndown updated. If you rejected even one valid
schema, the change is wrong regardless of how many invalid ones it caught.
