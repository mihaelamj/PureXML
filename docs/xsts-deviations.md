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

Only tests with a settled expectation are counted. The suite marks contested
entries `<current status="queried">` (disputed in W3C Bugzilla, the expected
validity itself in question, e.g. `\p{Lu}*` over two uppercase letters one of
which is an astral math capital); agreeing or disagreeing with a contested
expectation is not meaningful, so the runner skips them. Excluding the queried
entries removed about 70 apparent deviations that were never bugs.

## Baseline (settled expectations; after twelve fixes)

| Kind | First measurement | Now |
|---|---|---|
| valid schema rejected | 75 | 1 |
| invalid schema accepted | 2467 | 323 |
| valid instance rejected | 604 | 171 |
| invalid instance accepted | 582 | 155 |

Counts are against *settled* W3C expectations (queried/disputed entries excluded).

XSTS is a deliberately adversarial, exhaustive corpus; mature validators
(Xerces, libxml2) do not pass it fully. The goal is not a green number. It is to
fix the deviations that are genuine correctness bugs affecting real documents,
and to document the remainder as spec-justified, deliberate exclusions.

## Category A: genuine correctness bugs

### Fixed (thirty-one root causes, ~2255 deviations cleared)

list-datatype length facets (#146) · union pattern/enumeration facets · duration
partial-order facets · QName length non-constraining · the full XSD `\p{Is...}`
Unicode block set · element-level `block` against `xsi:type` · empty-element
default/fixed values + enumeration-restriction-replaces · `block="substitution"`
on substitution-group heads · `\w`/`\W` XSD definition · document-scoped
xs:ID/xs:IDREF uniqueness and resolution · `<xs:attribute ref>` resolution ·
mixed-content type with no element model · built-in `xsi:type` resolution gated
by substitution validity (the XSD Part 2 derivation lattice), which also closed
the two gaps it exposed (a simple-typed element rejecting stray attributes;
identity fields comparing in value space when the node carries an `xsi:type`) ·
compile-time constraining-facet definition validity (length-family facets are
`nonNegativeInteger`, co-occurrence and range order) · value-bound facet
validity (`min`/`maxInclusive`, `min`/`maxExclusive`, `enumeration` values valid
in the base space; inclusive/exclusive exclusions; bound ordering) · `gMonth`
`--MM--` lexical form · schema `id` attribute validity (`xs:ID`: NCName and
unique within the document). The schema-validity work brought invalid schemas
accepted 2461 to 884 (schema-document structural validity: content model + complexType content shape, attribute values, name/reference + pattern-regex lexical validity, and reference resolution, against the schema-for-schemas, plus simpleType variety constraints on list itemType and union memberTypes, plus targetNamespace scope matching on local schema references); see `schema-validity-burndown.md`.
Plus the measurement fix (exclude W3C-disputed `status="queried"` entries).

### Remaining, root-caused (the hard tail)

Each is a substantial, self-contained study, not a one-locus cluster fix:

| Cluster(s) | ~Count | Root cause (diagnosed) | Difficulty |
|---|---|---|---|
| `particlesOb/Je/Jf`, related | ~30 | `<xs:any>` defaults to `processContents="strict"`; the matched element's declaration lives in a *separate* schema document referenced only by the instance `xsi:schemaLocation` (no `<import>`). Needs multi-document schema loading + `xsi:schemaLocation` honoring, plus strict-wildcard semantics and Particle-Valid-Restriction. | large (new capability) |
| `reI` | ~10 | `pattern` values containing literal tab/newline: XML attribute-value normalization (tab/newline to space) versus the value's `whiteSpace` facet. The "right" pattern text depends on that interaction. | subtle |
| `test`, `elemT` | ~65 | heterogeneous grab-bags (MS "Additional"/element tests): many distinct minor causes, not one root cause. Each case needs individual triage. | per-case grind |
| `idF`, `idc` remainder | ~14 | identity-constraint selector/field XPath edge cases beyond the implemented core. The value-space comparison via instance `xsi:type` and built-in `xsi:type` resolution now land; what remains is the declared-type-driven value-space comparison (needs PSVI type assignment, since the field's declared simple type is not threaded into identity validation) and selector/field XPath edges. | moderate |
| `wildG`, `stZ`, `addB` | ~25 | wildcard-in-group composition, simple-type edge cases, attribute-default edges. | mixed |

The clean, single-root-cause, high-leverage fixes are exhausted. Reaching zero
on the instance buckets requires the multi-document-schema capability (the
largest single lever, ~30 cases) and per-case work on the grab-bags; neither is
a quick fix, and rushing them would violate the project's no-shortcuts ethic.

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

**Status (revised):** now being implemented as the general schema-for-schemas
mechanism, not a per-rule pile. The content-model pass has landed (`id` validity,
facet-definition validity, and the `allowedChildren` structural table), driving
invalid-schemas-accepted from 2461 to 1313. The remaining structural work (the
component **attribute model**, child order, particle semantics) continues under
`schema-validity-burndown.md`. A too-lenient compiler does not corrupt
valid-document validation, but rubber-stamping invalid schemas is the largest
conformance gap, so it is being closed rather than excluded.

## Category C: arguable / needs investigation

- `test`, `elemT` (invalid instance accepted, ~86): not yet sampled; classify before fixing.

## Category D: deliberate interpretations of spec-ambiguous points

These are resolved, not open: the spec underspecifies the point and the suite's
own contributors disagree, so a single behavior cannot satisfy all of them. We
pick the defensible reading and accept the residual deviation.

- **QName length facets are non-constraining.** XSD 1.0 Datatypes 4.3.1 defines
  the unit of length for string (characters), anyURI (characters), binary
  (octets), and list (items), but not for QName, so it is implementation-defined.
  NIST (36+ cases) and Xerces treat `length`/`minLength`/`maxLength` on QName as
  always satisfied; Microsoft (4 cases: `QName_length001/003`, `QName_minLength003`,
  `QName_maxLength001`) treats them as character counts and expects rejection.
  These are directly contradictory (NIST marks a 15-character value valid under
  `length=1`; MS marks `foofo` invalid under `length=4`). We chose
  non-constraining, matching Xerces and the larger NIST set, because a QName's
  value is an abstract (namespace, local-name) pair with no defined character
  length. Cost: the 4 MS cases remain in "invalid instances accepted". Fixing
  the 36+ NIST false rejections (valid documents wrongly rejected) is the more
  important direction.

- **RecurseAsIfGroup for a repeating element against a repeating choice
  (`particlesZ001`).** A derived `element{0,unbounded}` restricting a base
  `choice{0,unbounded}(element, any)`. The Microsoft test marks it valid, and its
  own documentation states the reason: "Particle Derivation OK (Elt:Choice --
  RecurseAsIfGroup) rule is ambiguous." Under the literal §3.9.6 rule (which
  Xerces follows) the element is wrapped as a one-member `{1,1}` synthetic group
  whose member keeps the element's `{0,unbounded}` occurrence, and that member
  must be a valid restriction of a `{1,1}` choice branch; `{0,unbounded}` does not
  fit `{1,1}`, so the strict reading rejects it. We follow the strict reading
  (matching the reference implementation), accepting this one residual "valid
  schema rejected". Adopting the lenient reading would require a special case that
  cannot be expressed without over-accepting genuinely invalid restrictions on
  PureXML's content-model representation (an attempt to do so regressed roughly
  thirty other cases). Tracked on #165. The sibling `particlesV003` (Sequence:Choice
  MapAndSum) was a genuine bug, since fixed.

## How a fix lands

Pick a Category A cluster, read 2-3 cases (schema + instance + expected) against
the spec text, fix the owning code, add a focused regression test, re-run
`swift test -c release --filter XSTS`, confirm the relevant count drops, and
ratchet the baseline in `Tests/XSTSSuiteTests.swift` down to the new value.
Tracking issues: #145 (invalid schema accepted), #146 (valid instance
rejected), #147 (invalid instance accepted), #148 (valid schema rejected).
