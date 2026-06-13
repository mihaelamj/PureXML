# Schema-validity burndown

The standing plan for closing the largest XSTS conformance gap. **Autopilot
contract:** follow this document iteration by iteration, each as its own PR with
a critic pass, until `invalid-schemas-accepted` is driven down to its
irreducible tail. Do not deviate to new features while this is open.

## The problem (measured 2026-06-13, 2006-11-06 archive)

| Bucket | Count | Reading |
|---|---|---|
| valid-schemas-rejected | 72 | we rarely reject a good schema |
| **invalid-schemas-accepted** | **2461 -> 1051** | we rarely catch a bad one (facet, id, and structural content-model validity landed) |
| valid-instances-rejected | 233 | (instance side, separately tracked) |
| invalid-instances-accepted | 165 | |

One-sentence diagnosis: *the validator runs its instance-validity rules but not
its schema-validity rules.* It compiles what it understands and ignores the
rest, so ~18% of the invalid-schema corpus is accepted silently.

Source split of the 2461: **2323 Microsoft, 138 Sun.** The Microsoft mass
spreads across every category (DataTypes 703, ComplexType 262,
IdentityConstraint 221, SimpleType 139, ModelGroups 137, Attribute 124,
Particles 118, Wildcards 97, Element 96, Notations 84, Group 82, Regex 74,
Schema 61, AttributeGroup 52, Additional 39, Annotations 30, Errata 4). No
single root cause; this is a campaign of distinct schema-component constraints.

## Where the checks belong

Schema-validity findings are reported at **compile time**, through
`PureXML.Validation.XSDSchema.consistencyErrors(...)` (called from
`SchemaDocument.Document.init`), which already throws `SchemaError.inconsistent`
when a named type violates a rule. New rule families are added there (or in a
sibling validation composed into it), never at instance-validation time. The
existing pattern: collect ALL findings, report them together.

## Priority order (highest leverage first, measured)

Each iteration targets one self-contained rule family with a clean root cause.

1. **Facet-definition validity** (XSD Part 2 §4.3). _Mostly done (2461 -> 1789)._
   Landed: length-family facet values must be `nonNegativeInteger`
   (`totalDigits` a `positiveInteger`); `length` excludes
   `minLength`/`maxLength`; `minLength` <= `maxLength`; `fractionDigits` <=
   `totalDigits`. Value-bound facets (`min`/`maxInclusive`,
   `min`/`maxExclusive`) and `enumeration` values must be valid in the base
   value space; `Inclusive` excludes `Exclusive` on each side; lower bound may
   not exceed (nor, if exclusive, equal) the upper. (The bound-value check
   exposed and fixed a `gMonth` `--MM--` lexical gap.) **Still open in this
   family:** facet applicability per base (`fractionDigits` only on
   decimal-derived, `length` only on string/binary/list, etc.); `whiteSpace`
   may not weaken an inherited value; facet repetition. Inherited-facet
   co-occurrence (across derivation steps) is deliberately not checked yet
   (current pass reads only the local restriction).
2. **`id` attribute validity** (xs:ID). _Done (1789 -> 1688)._ The `id`
   attribute on any XSD component is xs:ID: each value must be a valid NCName and
   unique within the schema document. Walks the schema-document tree, skipping
   `appinfo`/`documentation` foreign content and treating only the unprefixed
   `id` as the component identifier. Broad reach (idA-idK, attgA, attB, ctA).
3. **Component-name uniqueness.** Identity-constraint names unique per schema;
   type / element / attribute names unique per namespace; no duplicate attribute
   uses on a type. Cheap graph checks (~12 identity-constraint-name cases, plus
   type/element/attribute name collisions).
4. **Resolvable references.** _Done (1092 -> 1051)._ `type`/`base`/`itemType`/
   `memberTypes` types, `element`/`attribute`/`group`/`attributeGroup` `ref`, and
   element `substitutionGroup` must resolve to a declared component or a built-in
   (`SchemaReferences.swift`), matched by local name, skipped when
   `import`/`include`/`redefine` may supply externals. **Still open:** keyref
   `refer` resolution; the context-sensitive applicability rules (`form` on a
   global decl, `ref` excluding `name`/`type`).
5. **Facet applicability per base** (the open facet-family tail): which facets
   a base admits (`fractionDigits` only on decimal-derived, `length` only on
   string/binary/list, etc.), and a fixed facet may not be changed.
6. **Schema-for-schemas structural validity.** _Content-model pass done
   (1688 -> 1313, -375)._ A data-driven `allowedChildren` table (the schema-for-
   schemas child content model) rejects disallowed children, multi/misplaced
   `annotation`, and identity constraints missing selector/field, via one general
   mechanism (`SchemaStructure.swift`). Attribute **value** validity also landed (enumerated attributes, `minOccurs`/`maxOccurs`; 1313 -> 1190), plus **name/reference lexical validity** (`name` an NCName; `type`/`base`/`ref`/`itemType`/`refer`/`substitutionGroup` QNames; 1190 -> 1129), plus **`pattern` regex validity** (compile each pattern; reject only unambiguous syntax errors, tolerating engine gaps; 1129 -> 1092). **Still open:** attribute **applicability** (which attributes each component admits, e.g. `form` is prohibited on a global declaration, `ref` excludes `name`); child *order* beyond the leading annotation; and particle / model-group semantic rules (Unique Particle Attribution, Particle-Valid-Restriction completeness).

## Per-iteration protocol (the PR-critic-loop)

For each cluster, on a fresh branch off `main`:

1. **Scope & measure.** Identify the cluster's cases in
   `/tmp/xsts-failures.txt`; read a sample of the actual invalid schemas to pin
   the exact rule(s). State the rule in one sentence (first principles).
2. **Implement at the owning layer** (compile-time consistency check). Make
   impossible states unrepresentable where it helps; no special-case bandaids.
3. **Unit tests** for the rule: a valid schema passes, each invalid form is
   rejected with a located, specific message. Swift Testing.
4. **Gates** (all must pass): `bash scripts/check-style.sh`,
   `bash scripts/check-namespacing.sh`, `swiftformat . --config .swiftformat
   --lint`, `swiftlint --config .swiftlint.yml --strict`, `swift build`,
   `swift test`, `bash scripts/check-wasm.sh`.
5. **XSTS ratchet.** `XSTS_ROOT=/private/tmp/xsts/xmlschema2006-11-06 swift test
   -c release --filter XSTS`. `invalid-schemas-accepted` must fall;
   **no other bucket may rise** (hard gate). Update the pinned baselines in
   `Tests/XSTSSuiteTests.swift` to the new numbers.
6. **Critic pass (mandatory before merge).** Spawn an independent reviewer over
   `git diff main...HEAD`: correctness (does the rule over- or under-reject?
   spec citation), removed-behavior, cross-file impact, and altitude (is this a
   bandaid or the real rule?). Treat findings adversarially; fix every real one
   and re-run gates + XSTS. A finding that the rule is too aggressive (a valid
   schema now rejected) is a release blocker.
7. **Document & commit.** CHANGELOG entry with the before/after XSTS numbers;
   update this file's priority table and `docs/xsts-deviations.md`. Commit
   `<type>(schema): …`, then fast-forward merge to `main` (local only; never
   push, per policy). Delete the branch.

## Invariants

- The ratchet only falls. A rising bucket is a regression and blocks the merge.
- Disclosed limits are fine; silent debt is the violation. Until the schema side
  is solid the README must state the conformance numbers and what is not yet
  checked, and the package stays `0.x`.
- Apple/Swift-native only; no external SwiftPM deps; macOS + Linux + WASI.
