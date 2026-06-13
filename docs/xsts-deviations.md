# XSTS deviation worklist

This partitions the W3C XML Schema Test Suite (XSTS, 2006-11-06 archive)
deviations by **root cause and kind**, so the burn-down is driven by
understanding each rule rather than by chasing the count. First measured
2026-06-13; baselined and ratcheted in `Tests/XSTSSuiteTests.swift`.

## What the oracle measures

The runner compares PureXML's verdict to the suite's expected validity. A
schema is "accepted" iff `Schema.Document(source)` does not throw; an instance
is "accepted" iff `validate` returns no errors. The four counts:

| Kind | Meaning | Direction |
|---|---|---|
| valid schema rejected | legal XSD that PureXML refused to compile | too strict |
| invalid schema accepted | illegal XSD that PureXML compiled anyway | too lenient |
| valid instance rejected | valid document PureXML flagged | too strict |
| invalid instance accepted | invalid document PureXML passed | too lenient |

The oracle is binary and coarse: "invalid schema accepted" conflates *we have a
bug* with *we do not implement this validity constraint by design*. The point of
this document is to separate those.

## Baseline (post #146 list-facet fix)

| Kind | Count |
|---|---|
| valid schema rejected | 75 |
| invalid schema accepted | 2467 |
| valid instance rejected | 547 |
| invalid instance accepted | 555 |

XSTS is a deliberately adversarial, exhaustive corpus; mature validators
(Xerces, libxml2) do not pass it fully. The goal is not a green number. It is to
fix the deviations that are genuine correctness bugs affecting real documents,
and to document the remainder as spec-justified, deliberate exclusions.

## Category A: genuine correctness bugs (fix; real-data impact)

These are cases where PureXML mishandles a feature it does support. Each is a
real bug a user could hit with a well-formed schema and document.

| Cluster(s) | Count | Root cause | Locus | Status |
|---|---|---|---|---|
| `list-NMTOKENS/IDREFS/ENTITIES` length facets | ~84 | length on a built-in list counted characters, not items | `XSDSimpleParser.simpleType` | **fixed (#146)** |
| `union-*-pattern`, `union-*-enumeration` | ~200 | a union restricted by `enumeration`/`pattern` does not enforce the facet (value outside the enumeration is accepted) | `SimpleType.validateUnion` | open, one fix, high value |
| `atomic-duration-minInclusive/maxInclusive` | ~50 | duration ordering bounds not enforced | duration comparison | open |
| `reL`, `reI`, `RegexTest` (instance) | ~155 | missing Unicode block escapes (`\p{IsArmenian}` etc.) and category coverage in the regex engine | `Sources/Regex` | open, feature completion |
| `atomic-QName-length`, `-minLength` | ~36 | character-length facet wrongly applied to `QName`; the spec/NIST treat QName length as non-constraining (Xerces agrees) | length facet on QName | open, over-strict |
| `valueconstraint`, `isDefault` | ~26 | default/fixed value handling | element/attr defaults | open, needs sampling |
| `particlesJk/Jj/Ha/Q/R` (schema), `particlesOb/Je` (instance) | ~110 | content-model construction/validation edge cases | content model | open, bounded |
| `int_min/maxInclusive`, `int_min/maxExclusive` (schema) | ~16 | integer bound facets rejecting legal schemas | numeric facets | open, bounded |

Recommended order: union facets (~200, one fix) → QName length (~36) → regex
Unicode blocks (~155) → duration ordering (~50) → particles/int facets.

## Category B: schema-for-schemas validity (unimplemented by design)

The bulk of the 2467 "invalid schema accepted". PureXML compiles schemas
permissively: it reads the components it understands and ignores structurally
illegal content rather than validating the schema document against the
schema-for-schemas. Examples found:

- `ctB`: `<complexType>Annotation information</complexType>` (bare text content) is accepted.
- `notatF`: `<notation>` placed inside `<restriction>` (illegal position) is accepted.
- `idA/idB/idC`: malformed identity-constraint definitions accepted.
- `annotation/annotB`: illegal annotation placement accepted.
- `addB`, `stF`, `ctG`, `ctH`: assorted illegal component structures accepted.

| Cluster(s) | Count |
|---|---|
| `ctB/ctG/ctH` (complexType structure) | ~183 |
| `idA/idB/idC` (identity constraints) | ~118 |
| `notatF` (notation placement) | ~66 |
| `annotation/annotB` | ~62 |
| `addB`, `stF`, and the long tail | remainder of 2467 |

**Decision:** enforcing this is a large, low-real-world-value effort (people do
not author structurally broken schemas, and a too-lenient *compiler* does not
corrupt valid-document validation). It would require a schema-document
validation pass against the schema-for-schemas. Treated as a **documented,
deliberate exclusion** unless a concrete need arises. If implemented, it is its
own epic, not part of the instance-correctness burn-down.

## Category C: arguable / needs investigation

- `test`, `elemT` (invalid instance accepted, ~86): not yet sampled; classify before fixing.
- QName length (listed in A) is spec-murky; it sits in A because NIST and Xerces agree the instance is valid, so rejecting it is the defensible bug.

## How a fix lands

Pick a Category A cluster, read 2-3 cases (schema + instance + expected) against
the spec text, fix the owning code, add a focused regression test, re-run
`swift test -c release --filter XSTS`, confirm the relevant count drops, and
ratchet the baseline in `Tests/XSTSSuiteTests.swift` down to the new value.
Tracking issues: #145 (invalid schema accepted), #146 (valid instance
rejected), #147 (invalid instance accepted), #148 (valid schema rejected).
