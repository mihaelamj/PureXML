# Particle Valid (Restriction): the exact decision procedure

Status: design / derivation. No behaviour change. Companion to
[`production-readiness.md`](../production-readiness.md) (stopper 2) and
[`release-hurdles.md`](../release-hurdles.md) Part 1 (the false-negative tail is
this oracle's deliberate under-approximation).

## Why this document

Most of the remaining `invalid-schemas-accepted` tail (`particles*`, `elemZ`)
routes through ONE function, `ParticleRestriction.violation`
(`Sources/Schema/ParticleRestriction.swift`), which deliberately
*under-approximates* XSD 1.0 §3.9.6 "Particle Valid (Restriction)" to stay
false-positive-free. The tail is therefore not N independent bugs; it is one
algorithm implemented approximately. The Knuthian move is to derive the EXACT
decision procedure once, with the soundness (no-false-positive) argument for each
clause, and then make the oracle exact clause by clause behind that proof --
rather than patch cases. This document is that derivation. It is clean-room from
the W3C Recommendation §3.9.6 and the reference algorithm in Xerces-J
`XSConstraints.particleValidRestriction` (facts of the algorithm only).

## The problem, stated exactly

A particle is `(minOccurs, maxOccurs, term)` where the term is an element
declaration, a wildcard, or a model group (`sequence` | `choice` | `all`) of
particles. Given a derived particle `D` and a base particle `B`, decide whether
`D` is a **valid restriction** of `B`: every sequence of element/attribute
information items that `D` permits, `B` also permits, under the additional
element-identity constraints (name, type derivation, nillable, fixed value,
disallowed substitutions).

The two directions are NOT symmetric in cost:

- **Soundness (the sacred direction):** if `D` is a valid restriction, the
  procedure MUST accept it. A wrong rejection is a false positive -- the
  unrecoverable failure (stopper 1). Every clause below carries its soundness
  argument: *why accepting cannot be wrong*, or *why this clause never rejects a
  valid `D`*.
- **Completeness:** if `D` is not a valid restriction, the procedure SHOULD
  reject it. A miss is a tolerable, disclosed under-rejection (stopper 2). Where
  the spec's own rules are incomplete (they are -- see "Spec limitations"),
  completeness is bounded by the spec, not by us.

## The algorithm (XSD 1.0 §3.9.6, reference: Xerces `particleValidRestriction`)

### Step 0 -- empty particles (cos-particle-restrict.a/.b)

- If `D` is empty (admits only the empty sequence) and `B` is not emptiable ->
  invalid.
- If `D` is not empty and `B` is empty -> invalid.
- `D` empty and `B` emptiable -> valid (the content-free derived particle).

`ParticleRestriction.valid` already does this first (`contentFree`/`emptiable`).

### Step 1 -- normalization (pointless-group removal)

Replace a model group by its single child when the group is "pointless": a
group with one particle, or a `sequence`/`choice` nested directly in a
`sequence`/`choice` with compatible occurrence. Concretely Xerces walks to the
"non-unary group" (`getNonUnaryGroup`) and flattens pointless children
(`removePointlessChildren`) before dispatch. PureXML's `ParticleNormalization`
covers part of this; the derivation requires it to be applied to BOTH `D` and
`B` consistently before the dispatch, so the compositor pairing below is exact.

Soundness: normalization preserves the language exactly (a pointless group
admits the same sequences), so it can neither add nor remove a valid restriction.

### Step 2 -- substitution-group expansion (the structural gap)

If a term is a **global element** that is the head of a non-empty substitution
group, replace it by a `choice` over `{members…, head}` with the element's
occurrence range. (Xerces: `dSGHandler.getSubstitutionGroup`, "treat as CHOICE".)

This is the single biggest difference from the current PureXML oracle, which does
NO substitution-group expansion (a deliberate FP-safety choice inherited from the
UPA design, where QName-only overlap is correct). For **restriction**, expansion
is REQUIRED: a base element that is a substitution-group head permits any member,
so a derived particle restricting it must be checked against the choice-of-members
(XSTS `elemZ026`, `particlesV020`).

Soundness obligation (the proof that must hold before this is implemented): the
expanded choice must be *exactly* the set of elements the head permits in an
instance -- `{head} ∪ {members transitively substitutable for head, minus those
blocked by the head's {disallowed substitutions}}`, each with occurrence `1,1`
inside the choice and the choice carrying the head particle's `minOccurs,maxOccurs`.
If the expansion is a strict superset of the true substitutable set, a valid `D`
can be rejected (false positive). Therefore expansion must apply `block`/`final`
filtering exactly, and only to GLOBAL heads (local elements head no group). This
is the FP-critical proof; it gates the V020/elemZ026 closure.

### Step 3 -- effective total range

For the cardinality clauses, compute `D`'s effective total occurrence range
`[minETR, maxETR]`:

- element / wildcard: `[min, max]`.
- `choice` of children `cᵢ`: `min·minᵢ.min summed as min over branches`,
  precisely `min = minOccurs · (Σ over branches of 0 if branch emptiable else
  min of branch minETR)`… use the spec's "effective total range (all and
  sequence)" and "(choice)" definitions verbatim:
  - sequence/all: `minETR = minOccurs · Σ childMinETR`, `maxETR = maxOccurs ·
    Σ childMaxETR` (unbounded if any child or occurrence is unbounded).
  - choice: `minETR = minOccurs · min(childMinETR)`, `maxETR = maxOccurs ·
    max(childMaxETR)`.

PureXML has `effectiveOccurrenceMin/Max`; the derivation pins these to the spec
formulas so MapAndSum and NSRecurseCheckCardinality are exact.

### Step 4 -- dispatch (derived compositor × base compositor -> rcase)

| D \ B | element | wildcard | sequence | choice | all |
|---|---|---|---|---|---|
| **element** | NameAndTypeOK | NSCompat (admits) | RecurseAsIfGroup | RecurseLax | RecurseAsIfGroup |
| **wildcard** | -- invalid | NSSubset (narrows) | -- invalid | -- invalid | -- invalid |
| **sequence** | -- invalid | NSRecurseCheckCardinality | Recurse | MapAndSum | RecurseUnordered |
| **choice** | -- invalid | NSRecurseCheckCardinality | -- invalid | RecurseLax | -- invalid |
| **all** | -- invalid | NSRecurseCheckCardinality | -- invalid | -- invalid | Recurse |

(A derived group restricting a base **element** is invalid except the
content-free case handled at Step 0 -- PureXML's `(.group,.element) -> false`,
already correct, XSTS `particlesHb011`. RecurseAsIfGroup = `checkRecurse` with the
derived element wrapped as a one-particle group `(1,1)`.)

### Step 5 -- the rcases

- **NameAndTypeOK** (elt:elt): same name+targetNamespace; `D` nillable ⟹ `B`
  nillable; `checkOccurrenceRange(D,B)` (`B.min ≤ D.min` and `D.max ≤ B.max`);
  if `B` is fixed, `D` must be fixed to the same value (value-space, not lexical);
  `D`'s type validly derived (by restriction/extension as allowed) from `B`'s; and
  `D`'s {disallowed substitutions} ⊇ `B`'s. PureXML's element:element case
  (`ParticleRestriction.valid`, line 69) covers name/occurrence/block/nillable/
  fixed/type; gaps are the type-derivation subtleties (Ig004/Ik011/025/027 --
  union-member by-NAME derivation, see Spec limitations).

- **Recurse** (seq:seq, all:all, RecurseAsIfGroup elt:seq/all): an order-preserving
  injection of `D`'s particles into `B`'s -- each `Dᵢ` is a valid restriction of the
  matched `Bⱼ` with indices strictly increasing, and every unmatched `Bⱼ` is
  emptiable. Soundness: an order-preserving injection witnesses that every `D`
  sequence is a `B` sequence; accepting requires the witness, so accepting is never
  wrong.

- **RecurseLax** (choice:choice, elt:choice): each `Dᵢ` is a valid restriction of
  SOME `Bⱼ` (order-preserving but base branches may be skipped freely; no
  emptiable obligation since a choice need not consume a branch).

- **RecurseUnordered** (seq:all): each `Dᵢ` restricts some `Bⱼ`, each `Bⱼ` used at
  most once, unmatched `Bⱼ` emptiable. (All-groups are order-free.)

- **MapAndSum** (seq:choice): each `Dᵢ` restricts some base branch AND the
  effective total range of `D` is within `B`'s -- `[minETR(D), maxETR(D)] ⊆
  [B.min, B.max]` with the per-particle count product. PureXML approximates this
  by per-particle checks (`ParticleRestriction.swift:8`); the exact form is the
  effective-total-range containment from Step 3 (XSTS `particlesV020` also needs
  Step 2).

- **NSRecurseCheckCardinality** (group:wildcard): every leaf the group can
  contain is admitted by the wildcard, and `[minETR(D), maxETR(D)] ⊆ [B.min,
  B.max]`. PureXML has this (`leavesAdmitted` + `rangeWithinWildcard`).

## Empirical finding (2026-06-23): the keystone's targets are CONTESTED, not gaps

Probing the actual XSTS cases overturned this document's first hypothesis that
substitution-group expansion (Step 2) closes `elemZ026` / `particlesV020`. Both
are the same pattern: a derived `ref` to a substitution-group MEMBER restricting a
base `ref` to the HEAD (`elemZ026`: `ref restrictedBasicBit` restricts
`ref basicBit`; `V020`: `ref bar` restricts `ref SUB`). Measured behaviour
(`SRProbe`): PureXML ALREADY ACCEPTS these, and the substitution-group link is the
cause -- the same schema with the member NOT in the head's substitution group is
correctly rejected (`NameAndTypeOK` name mismatch). PureXML's content model
expands a head `ref` to admit its members (required for instance validation), and
the restriction oracle inherits that, giving the **Xerces-lenient** reading.

So these are CONTESTED, not closeable: PureXML + Xerces accept (a member is a
valid restriction of its head via expansion); XSTS rejects under strict
`NameAndTypeOK` (names differ, no expansion). The keystone (ADDING expansion)
would entrench the acceptance, the opposite of closing them. Closing them would
require a separate NON-expanded restriction view AND reverses the deliberate
leniency -- a false-positive risk against schemas the spec's expansion reading and
Xerces accept. There is therefore NO clean FP-safe conformance win in the exact
oracle: every remaining particle case is contested (`elemZ026`/`V020`/`Ig004`
`#all`-collapse) or FP-delicate (`Ik011/025/027` union-member, which already
regressed `addB150`), or a deliberate anti-over-rejection divergence
(`Ha161`/`M034`, which protect `particlesZ001`). The proof-first discipline earned
its keep: it prevented shipping the keystone against contested targets.

## Where the current oracle approximates (and why each is NOT a clean win)

| Clause | Current | "Exact" form | XSTS | Verdict |
|---|---|---|---|---|
| Substitution-group expansion | already expands (lenient) | strict non-expanded restriction view | elemZ026, V020 | CONTESTED (Xerces/PureXML accept, XSTS rejects); closing risks FP |
| MapAndSum | per-particle approx (line 8) | Step 3 effective-total-range | V020 | V020 is contested above; MapAndSum exactness alone closes nothing |
| RecurseAsIfGroup in-branch order | bounded under-rejection | exact Recurse with sequencing | M034 | DEFERRED: exact form over-rejects `particlesZ001` (spec dispute) |
| NameAndTypeOK type derivation | value-space | by-NAME union-member derivation | Ig004, Ik011/025/027 | Ig004 contested (#all-collapse); Ik FP-delicate (addB150) |

## Spec limitations (genuine, not bugs -- name and bound them)

XSD 1.0 §3.9.6 is **not a complete decision procedure for language
containment**; its rules are a sound-but-incomplete syntactic approximation
chosen by the WG. Consequences this oracle must respect:

- **Ha161 / particlesZ001 tension:** the literal RecurseAsIfGroup rule marks
  `Ha161` invalid but over-rejects `particlesZ001`, which the W3C reads valid.
  Making RecurseAsIfGroup "exact to the literal rule" reintroduces an FP on Z001.
  This is a contested point in the spec rules themselves; the current oracle's
  first-principles reading (accept both) is the FP-safe choice. Closing Ha161
  REQUIRES resolving the Z001 contradiction, which is spec adjudication, not code.
- **mgO013 (redefine):** Xerces rejects the schema (src-redefine.6.2.2), XSTS keeps
  it valid + rejects the instance. Contested; out of scope for this oracle.
- **NameAndTypeOK union members (Ik cluster):** the spec's NameAndTypeOK requires
  `D`'s type to be validly derived from `B`'s. For a union base, `D`'s type must be
  one of the union's members BY IDENTITY, not merely value-space-restricting the
  union (a value-space check accepts a separate type sharing the base -- addB150 is
  valid, Ik025 invalid on exactly this distinction). The exact rule needs
  derivation-by-name; a naive value-space tightening already regressed addB150
  (recorded in CHANGELOG). FP-delicate; close only with the by-name derivation.

## Conclusion (after the empirical finding): no clean conformance win remains

The derivation stands as the correct reference algorithm and the soundness
framework, but applying it to the actual XSTS tail shows every remaining particle
case is contested or FP-delicate (see the table and finding above). Concretely:

- Substitution-group expansion: NOT a gap -- PureXML already expands (lenient,
  Xerces-aligned). elemZ026/V020 are contested; closing them risks an FP.
- MapAndSum exactness: closes nothing on its own (its only target, V020, is
  contested on the subst-group axis, not the cardinality axis).
- NameAndTypeOK union-member / Ig004: FP-delicate (addB150) / contested (#all).
- RecurseAsIfGroup exact: deferred (Ha161/Z001 spec dispute).

So the exact-oracle keystone does NOT escape the contested tail; there is no
FP-safe particle-restriction change to ship. The remaining lever toward the full
bar is therefore NOT conformance but the proven resource bound: the pushdown / RTN
content matcher (stopper 4), which is provable, non-contested, and independent of
this oracle. That is where the program continues.

If a particle clause is ever attempted, the discipline holds: derive the
soundness argument here first, implement behind the full XSTS `valid-*-rejected =
0` gate AND a dedicated adversarial over-rejection critic (the gate is
corpus-bounded; the critic constructs the inputs the corpus misses, as it did for
the attribute-wildcard rework), and disclose any residual under-rejection. Proof
on paper precedes the change to the oracle.
