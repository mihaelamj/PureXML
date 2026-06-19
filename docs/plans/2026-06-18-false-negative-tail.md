# XSTS false-negative tail: clause-by-clause closure

**Goal:** Drive the remaining false-negative buckets to zero without ever
raising either false-positive bucket.
**Approved design:** Current-session design: freeze the 79-case tail, split it by
owning oracle, add adversarial valid fixtures before tightening each rule, and
ratchet one clause at a time.

## Current measurement

Measured from `/tmp/xsts-failures.txt`, last written 2026-06-19 08:47 local time
by `XSTSSuiteTests`.

```sh
awk -F': ' '/invalid schema accepted/ {schema++} /invalid instance accepted/ {inst++} /valid schema rejected/ {vs++} /valid instance rejected/ {vi++} END {print "valid schema rejected", vs+0; print "invalid schema accepted", schema+0; print "valid instance rejected", vi+0; print "invalid instance accepted", inst+0}' /tmp/xsts-failures.txt
```

Result:

| Bucket | Count |
|---|---:|
| valid schema rejected | 0 |
| invalid schema accepted | 43 |
| valid instance rejected | 0 |
| invalid instance accepted | 31 |

The false-positive buckets are already zero. That is the non-negotiable gate:
every task below must keep them at zero.

Progress since the starting 48/31 snapshot: `particlesZ018` is closed by the
simpleContent inline type-restriction rule, and `ctZ010d` is closed by the
complexContent mixed-agreement rule. `stZ048` is closed by the substitution-head
`xs:anySimpleType` member content check. `elemZ027_c` is closed by making
substitution-group closure stop chaining through members whose own `block`
contains `substitution`. `elemZ028e` is closed by carrying global element-ref
declaration metadata into NameAndTypeOK, so a local implicit-`anyType` element
cannot widen a typed global ref. The schema false-negative bucket is down by
five with both false-positive buckets still at zero.

## File map

| Path | Change | Notes |
|---|---|---|
| `docs/plans/2026-06-18-false-negative-tail.md` | new | This plan and the seed manifest. |
| `Tests/XSTSSuiteTests.swift` | edit per fix | Ratchet only after a full XSTS run proves a count fell and no other bucket rose. |
| `CHANGELOG.md` | edit per fix | Record the exact before/after bucket movement and false-positive result. |
| `docs/release-hurdles.md` | edit per phase | Keep the release blocker summary current. |
| `docs/xsts-deviations.md` | edit per phase | Move cases between fixable, disclosed, and closed categories. |
| `docs/schema-validity-burndown.md` | edit per schema fix | Preserve the historical burndown and rule-family status. |
| `Sources/Schema/ParticleRestriction.swift` | likely edit | High-fan-in particle restriction oracle. |
| `Sources/Schema/ParticleRestrictionElement.swift` | likely edit | NameAndTypeOK type-derivation and union-member clauses. |
| `Sources/Schema/ParticleRestrictionHelpers.swift` | likely edit | Fixed value, wildcard strength, range helpers. |
| `Sources/Schema/ContentModelDeterminism.swift` | likely edit | UPA, especially wildcard overlap. |
| `Sources/Schema/SchemaRedefineSelfReference.swift` | likely edit | Redefine self-reference and cross-container restriction rules. |
| `Sources/Schema/SchemaReferences.swift` | likely edit | Include/import/redefine reference and composition validity. |
| `Sources/Schema/SchemaSubstitutionType.swift` | likely edit | Substitution-group member derivation. |
| `Sources/Schema/XSDSubstitutionMembers.swift` | likely edit | Instance substitution-group filtering. |
| `Sources/Schema/IdentityValidator*.swift` | likely edit | Remaining identity-constraint instance false negatives. |
| `Sources/Schema/SimpleType.swift` | likely edit | Simple-type derivation, regex, and value-space edges. |
| `Sources/Regex/*` | likely edit | Regex cases that are genuine errors, not disclosed engine gaps. |
| `Tests/XSDParticleRestrictionTests.swift` | edit per particle fix | Add invalid and adversarial valid fixtures. |
| `Tests/ContentModelDeterminismTests.swift` | edit per UPA fix | Add wildcard ambiguity and valid deterministic controls. |
| Existing `Tests/Schema*Tests.swift` suites | edit per fix | Add focused tests near the owning rule. |

## Seed manifest

Every row is a current accepted-invalid case. The lane is a starting hypothesis,
not a proof. Before code, read the XSTS fixture, the matching PureXMLResearch
reference, and the XSD 1.0 rule text; update the lane if the evidence says this
classification is wrong.

### Invalid schemas accepted: 43

| Lane | Cases | First owning surface |
|---|---|---|
| Schema-for-schemas / XSD self-schema edge | `xsd013`, `xsd014` | `SchemaStructure`, `SchemaReferences` |
| Additional-suite element/substitution triage | `addB009`, `addB177` | `SchemaSubstitutionType`, `SchemaReferences` |
| Attribute group restriction triage | `attgC028` | `SchemaAttributeRestriction`, redefine machinery |
| Attribute type/use triage | `attKa015`, `attKb018a` | `SchemaAttributeApplicability`, `SchemaAttributeRestriction` |
| Attribute identity/composition triage | `attQ011`, `attQ016`, `attQ017`, `attQ018` | Attribute restrictions and per-document composition |
| Substitution-group head/member modeling | `elemZ026` | `SchemaSubstitutionType`, `XSDSubstitutionMembers` |
| ParticleRestriction exactness | `particlesEa025`, `particlesFb003`, `particlesHa161`, `particlesHb011`, `particlesIg004`, `particlesIj008`, `particlesIk011`, `particlesIk025`, `particlesIk027`, `particlesK006`, `particlesM034`, `particlesV020` | `ParticleRestriction*` |
| UPA / wildcard determinism | `particlesZ022`, `particlesZ030_d`, `particlesZ039` | `ContentModelDeterminism` |
| Regex disclosed-vs-fixable triage | `reK88`, `RegexTest_993`, `RegexTest_1477` | `Sources/Regex/*`, `SimpleType` |
| Redefine / composition | `schG10`, `schM4`, `schM8`, `schN10`, `schN12`, `schZ011_a`, `schZ011_b`, `schZ011_c`, `schZ011_d` | `SchemaReferences`, `SchemaRedefineSelfReference`, `ParticleRestriction` |
| Wildcard UPA | `wildI009`, `wildI013`, `wildI014`, `wildZ013` | `ContentModelDeterminism` |

### Invalid instances accepted: 31

| Lane | Cases | First owning surface |
|---|---|---|
| Target namespace / form matching | `targetns00101m/targetNS00101m1_n` | `ComplexValidator*`, reference resolution |
| Disallowed substitution | `disallowedsubst00105m/disallowedSubst00105m1_n`, `disallowedsubst00106m2/Negative` | `XSDSubstitutionMembers`, `ComplexValidatorXSIType` |
| Nillability | `nillable00201m/nillable00201m2_n` | `XSDParserHelpers`, instance validator |
| Type derivation | `typedef00204m/typeDef00204m1_n` | `ComplexValidatorXSIType`, derivation tables |
| Additional-suite instance triage | `addB065/addB065.i` | to classify from fixture |
| Datatype value-space edges | `anyURI_a004_1339/anyURI_a004_1339.i`, `dateTime011_2008/dateTime011_2008.i` | `SimpleType` |
| Element constraints | `elemO011/elemO011.i`, `elemT074/elemT074.i` | instance validator, element declarations |
| Identity constraints | `idG006/idG006.i`, `idK012/idK012.i`, `idZ010/idZ010.i`, `idZ012/idZ012.i` | `IdentityValidator*` |
| Model group instance matching | `mgO013/mgO013.i`, `mgZ001/mgZ001.i` | `ContentMatcher`, `ParticleRestriction` fallout |
| Known particle under-rejection fallout | `particlesZ001/particlesZ001.i` | `ParticleRestriction` |
| Regex instance edges | `reT17/reT17.i`, `reT38/reT38.i`, `RegexTest_422/RegexTest_422.i`, `RegexTest_430/RegexTest_430.i`, `reZ006i/reZ006i.i` | `Sources/Regex/*`, `SimpleType` |
| Schema composition instance fallout | `schA2/schA2.i`, `schA5/schA5.i`, `schA7/schA7.i`, `schU3/schU3.i`, `schU4/schU4.i`, `schU5/schU5.i` | schema composition and instance validator |
| Simple-type instance edge | `stZ056/stZ056.i` | `SimpleType` |
| Wildcard instance matching | `wildZ013a/wildZ013a.i`, `wildZ013d/wildZ013d.i` | `ContentMatcher`, wildcard declaration lookup |

## Tasks (ordered)

### T1. Promote the manifest into the working loop

**Files:** `docs/plans/2026-06-18-false-negative-tail.md`,
`docs/xsts-deviations.md`

**Does:** Keep the 79-case seed manifest current as work lands. Every case is
classified exactly once as open-fixable, open-disclosed, closed, or reclassified
with reason. If a new XSTS run changes the failure list, update the manifest in
the same change that ratchets the baseline.

**Verifies:**

```sh
awk -F': ' '/invalid schema accepted/ {schema++} /invalid instance accepted/ {inst++} /valid schema rejected/ {vs++} /valid instance rejected/ {vi++} END {print vs+0, schema+0, vi+0, inst+0}' /tmp/xsts-failures.txt
```

**Commit:** `docs(xsts): freeze false-negative tail manifest`

### T2. Close low-fan-in non-particle cases first

**Files:** likely `Sources/Schema/SimpleType.swift`, `Sources/Regex/*`,
`Sources/Schema/SchemaSimpleTypeValidity.swift`, focused `Tests/Schema*Tests.swift`

**Does:** Start with cases that do not route through `ParticleRestriction`:
datatype instance cases and regex cases. `particlesZ018`, `ctZ010d`, and
`stZ048` are closed by the first passes.
For regex, first decide whether each case is a genuine unsupported-pattern
under-rejection or a spec-backed error. Disclosed cases must be documented, not
silently left in the bucket.

**Verifies:**

```sh
swift test --filter Schema
XSTS_ROOT=/private/tmp/xsts/xmlschema2006-11-06 swift test -c release --filter XSTS
```

**Commit:** `fix(schema): close simple-type false-negative tail`

### T3. Add wildcard UPA without changing particle restriction

**Files:** `Sources/Schema/ContentModelDeterminism.swift`,
`Tests/ContentModelDeterminismTests.swift`

**Does:** Handle wildcard overlap for `wildI*`, `wildZ013`, `particlesZ022`,
`particlesZ030_d`, and `particlesZ039`. Add adversarial valid content models:
disjoint wildcards, element plus non-overlapping wildcard, same-source wildcard
cases that remain deterministic, and namespace-qualified variants.

**Verifies:**

```sh
swift test --filter ContentModelDeterminismTests
XSTS_ROOT=/private/tmp/xsts/xmlschema2006-11-06 swift test -c release --filter XSTS
```

**Commit:** `fix(schema): detect wildcard UPA ambiguity`

### T4. Separate substitution-group modeling from particle exactness

**Files:** `Sources/Schema/SchemaSubstitutionType.swift`,
`Sources/Schema/XSDSubstitutionMembers.swift`,
`Sources/Schema/ParticleRestrictionElement.swift`,
`Tests/SchemaSubstitutionTypeTests.swift`,
`Tests/SchemaSubstitutionBlockTests.swift`

**Does:** Model the remaining `elemZ026` schema failure and
the `disallowedsubst*` instance failures without changing the general
MapAndSum/RecurseAsIfGroup logic. The key safety check is that a substitution
head/member graph must be namespace-exact and must not conflate same-local names.

**Verifies:**

```sh
swift test --filter SchemaSubstitution
XSTS_ROOT=/private/tmp/xsts/xmlschema2006-11-06 swift test -c release --filter XSTS
```

**Commit:** `fix(schema): model substitution group restriction edges`

### T5. Tighten NameAndTypeOK union and type clauses

**Files:** `Sources/Schema/ParticleRestrictionElement.swift`,
`Sources/Schema/ParticleRestrictionHelpers.swift`,
`Tests/XSDParticleRestrictionTests.swift`

**Does:** Target `particlesIg004`, `particlesIj008`, and
`particlesIk011`/`025`/`027`. Before code, write valid controls where a
restriction type derives from a valid union member and must still compile.
Do not replace union membership with a simple chain walk; that is the known
false-positive trap.

**Verifies:**

```sh
swift test --filter XSDParticleRestrictionTests
XSTS_ROOT=/private/tmp/xsts/xmlschema2006-11-06 swift test -c release --filter XSTS
```

**Commit:** `fix(schema): enforce NameAndTypeOK union restriction`

### T6. Make one ParticleRestriction clause exact at a time

**Files:** `Sources/Schema/ParticleRestriction.swift`,
`Sources/Schema/ParticleRestrictionHelpers.swift`,
`Tests/XSDParticleRestrictionTests.swift`

**Does:** Work in this order, stopping after each clause for a full XSTS gate:

1. `MapAndSum` Sequence:Choice: `particlesV020`.
2. `RecurseAsIfGroup` Elt:All/Elt:Sequence: `particlesK006`, `particlesM034`.
3. Remaining element/group and group/wildcard edge cases:
   `particlesEa025`, `particlesFb003`, `particlesHa161`, `particlesHb011`.

Each clause needs both invalid fixtures and valid near-misses. A valid near-miss
is mandatory because this is the highest-fan-in false-positive surface in the
repo.

**Verifies:**

```sh
swift test --filter XSDParticleRestrictionTests
XSTS_ROOT=/private/tmp/xsts/xmlschema2006-11-06 swift test -c release --filter XSTS
```

**Commit:** `fix(schema): make particle restriction clause exact`

### T7. Close redefine and composition fallout

**Files:** `Sources/Schema/SchemaReferences.swift`,
`Sources/Schema/SchemaRedefineSelfReference.swift`,
`Sources/Schema/SchemaCompositionValidations.swift`,
`Tests/SchemaRedefineAttributeGroupTests.swift`,
`Tests/SchemaGroupRedefineRestrictionTests.swift`,
`Tests/SchemaReferenceTests.swift`

**Does:** Target `schG10`, `schM4`, `schM8`, `schN10`, `schN12`,
`schZ011_a` through `schZ011_d`, and the related `schA*`/`schU*` instance
fallout. Every name lookup must be namespace-gated and bounded to the owning
schema container. Self-reference handling must be tested with nested local
definitions so the walk cannot overreach.

**Verifies:**

```sh
swift test --filter SchemaRedefine
swift test --filter SchemaReference
XSTS_ROOT=/private/tmp/xsts/xmlschema2006-11-06 swift test -c release --filter XSTS
```

**Commit:** `fix(schema): close redefine false-negative tail`

### T8. Close identity-constraint instance tail

**Files:** `Sources/Schema/IdentityValidator*.swift`,
`Sources/Schema/XSDParserHelpers.swift`,
`Tests/XSDIdentityTests.swift`,
`Tests/SchemaIdentity*Tests.swift`

**Does:** Target `idG006`, `idK012`, `idZ010`, and `idZ012`. Classify whether
each is selector/field XPath, default/fixed value, typed-value equality, or
keyref closure. Add a valid paired case for every invalid fixture.

**Verifies:**

```sh
swift test --filter Identity
XSTS_ROOT=/private/tmp/xsts/xmlschema2006-11-06 swift test -c release --filter XSTS
```

**Commit:** `fix(schema): close identity constraint instance tail`

### T9. Design the counting automaton separately

**Files:** new `docs/design/` or `docs/plans/` design artifact,
`Sources/Schema/ContentMatcher.swift`,
`Sources/Schema/ContentModelDeterminism.swift`,
`Tests/ContentMatcherDifferentialTests.swift`,
`Tests/ContentNFAStateBudgetTests.swift`

**Does:** Do not mix resource-bound architecture with conformance fixes. The
acceptance criteria for this later arc are: delete `occursUnrollCap`,
`totalStateCap`, and `positionCap`; remove silent "degrade to star" behavior;
state a worst-case time and memory bound; prove high numeric occurrence bounds
do not create proportional states.
The design artifact is `docs/design/counted-content-automaton.md`; implementation
must follow that proof plan rather than adding another cap.

**Verifies:**

```sh
swift test --filter ContentMatcher
swift test --filter ContentModelDeterminism
swift test --filter ContentNFAStateBudgetTests
```

**Commit:** `docs(schema): design counted content automaton`

## Constraints

- False positives stay at zero. A rise in `valid-schemas-rejected` or
  `valid-instances-rejected` blocks the change.
- Before changing parser, schema, validation, or typed-conversion behavior, read
  the matching PureXMLResearch fixture/reference and the XSD rule text.
- External validators are witnesses, not ground truth. If libxml2/Xerces and the
  spec disagree, document the disagreement and choose the defensible spec reading.
- No new SwiftPM dependencies, C targets, generated parser runtime, Foundation-only
  workaround, or JavaScript tooling.
- One rule family per implementation commit. Do not combine a particle oracle
  change with identity, regex, or composition work.
- Every under-rejection that remains by design must be named, bounded, and visible
  in `docs/xsts-deviations.md`; no silent acceptances.

## Test plan

Every implementation task runs, at minimum:

```sh
bash scripts/check-style.sh
bash scripts/check-namespacing.sh
bash scripts/check-forbidden-patterns.sh
swiftformat . --config .swiftformat --lint
swiftlint --config .swiftlint.yml --strict
swift build
swift test
XSTS_ROOT=/private/tmp/xsts/xmlschema2006-11-06 swift test -c release --filter XSTS
bash scripts/check-wasm.sh
```

Use targeted Swift tests before the full gate, but never claim a conformance
fix complete without the full XSTS ratchet.

## Done definition

- `Tests/XSTSSuiteTests.swift` reports:
  - `valid-schemas-rejected = 0`
  - `invalid-schemas-accepted = 0`
  - `valid-instances-rejected = 0`
  - `invalid-instances-accepted = 0`
- `docs/xsts-deviations.md` has no unclassified false negative.
- `docs/release-hurdles.md` is updated to move the false-negative tail from
  "biggest hurdle" to closed, leaving only the counted-automaton resource-bound
  work if that has not landed.
- All relevant local gates pass, including WASI.
- CHANGELOG records the final XSTS zeroing and any named spec divergences.
