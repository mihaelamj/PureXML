# Release hurdles to 1.0 (analysis)

Companion to [`production-readiness.md`](production-readiness.md) (the four
stoppers) and [`roadmap.md`](roadmap.md) (milestones). This characterizes, with
evidence, what actually stands between the current engine and a 1.0 fit to put in
front of a developer as the authority on XML/XSD correctness.

Snapshot at time of writing: v0.2.0 released; full 2006-11-06 XSTS archive (14383
groups) with `valid-schemas-rejected = 0`, `invalid-schemas-accepted = 11`,
`valid-instances-rejected = 0`, `invalid-instances-accepted = 15`.

## Status against the four stoppers

1. **Rejecting valid input (false positives).** `valid-schemas-rejected = 0` and
   `valid-instances-rejected = 0` on the **full** XSTS archive, corroborated by the
   libxml2 differential over 9618 schemas. **Met.** This is the doc's bar to be "an
   authority"; it is cleared on the measured corpora.
2. **Silently accepting faulty input (false negatives).** `invalid-schemas-accepted
   = 11`, `invalid-instances-accepted = 15`. **Not at 0.** This is the bulk of named
   milestone work (M2, M3) and the subject of Part 1 below.
3. **Uncharacterized correctness.** Differential harness vs libxml2 and a fuzz
   suite exist (M1, ~done). Gap: real-world corpora beyond XSTS, and the silent
   under-rejections noted in Part 2.
4. **Interactive safety.** Located diagnostics (#169) done; validation reports all
   errors (recoverable). Gap: a *proven* worst-case time/memory bound. The engine
   uses caps, which the standard explicitly disqualifies ("a cap is a band-aid, not
   a bound"). Subject of Part 2.

## The biggest hurdle, stated plainly

Driving the false-negative buckets (`invalid-schemas-accepted = 11`,
`invalid-instances-accepted = 15`) to zero is the largest remaining body of named
work, and it is hard for a specific reason: **the ~95% already closed were the
tractable cases; every case left fights the cardinal rule.** The remainder sits in
shared-oracle / contested-spec / multi-document-composition territory where the fix
risks introducing a false positive (the unrecoverable failure), needs spec
adjudication rather than code, or needs machinery not yet built.

The close, under-weighted runner-up is **proven (not capped) interactive resource
bounds.** Caps that silently skip checks disqualify the tool for the IDE use case no
matter how good the conformance numbers get.

The two are different in kind: Part 1 is many small adversarial edits to one
high-fan-in oracle; Part 2 is one foundational re-architecture.

## Part 1: the false-negative tail is one shared oracle's deliberate under-approximation

Nearly all of the remaining `particles*` / `elemZ` schema cases route through a
single function, `ParticleRestriction.violation`
(`Sources/Schema/ParticleRestriction.swift`), and fail exactly where that function
chose to under-approximate to stay false-positive-free.

| Cases | Clause needing tightening | Current posture |
|---|---|---|
| particlesIg004, Ij008, Ik011/025/027 | NameAndTypeOK (elt:elt), type-derivation / fixed / nillable / block | implemented, not catching these |
| particlesV020 | MapAndSum (Sequence:Choice) | effective-total-range "approximated by per-particle checks, a documented simplification" (ParticleRestriction.swift:8) |
| particlesK006, M034 | RecurseAsIfGroup (Elt:All, Elt:Sequence) | "a documented, bounded under-rejection… over-rejection is the non-starter" (ParticleRestriction.swift:298) |
| particlesEa025, Fb003, Ha161, Hb011 | pointless-particle / extension-from-`any` / forbidden sequence:elt | partial |
| elemZ026 | element-decl restriction where base is a substitution-group head | partially modelled; elemZ027_c and elemZ028e are closed |
| particlesZ018 | list-of-int ⊄ decimal (simple-type derivation, a *different* oracle) | closed by inline simpleContent type restriction check |
| ctZ010d | mixed base extended with new element content by a default-false derived type (a *different* oracle) | closed by complexContent mixed-agreement check |
| particlesZ022/030 | non-deterministic wildcards (UPA, not restriction) | determinism check is deliberately QName-only |

**Why this is the risk, by fan-in.** `ParticleRestriction.violation` is called from
`restrictionsAreSubsets` (every complex-type restriction in the corpus),
`anonymousRestrictionsValid`, `complexExtensionBaseValid`, `SchemaExtensionAllGroup`,
`SchemaAttributeRestriction`, `SchemaSubstitutionType`, and the redefine-group rule.
A single edit to make MapAndSum or RecurseAsIfGroup *exact* is therefore
re-evaluated against every type-restriction relationship in the 14383-group corpus
plus every valid schema in the wild. It is the highest fan-in false-positive surface
in the codebase.

**Why the direction is asymmetric.** These cases are invalid restrictions slipping
through because the rule accepts a slightly-too-large derived language. Tightening
the bound to catch them can clip a *valid* restriction (over-reject), the
unrecoverable failure. Type-derivation completeness is exactly where prior FP-delicate
work landed (atomic-not-derived, baseless-complex, list/union-only-from-anySimpleType).

**Consequence.** Roughly 12 of these are closeable only by making the oracle exact,
and each such change is a slow, adversarially-verified edit (gate for corpus FPs +
critic for latent FPs the corpus misses), not a pattern sweep. A few (contested
spec: schM4 reorder, attQ per-document vs per-composition id-scope) need adjudication,
not code.

## Part 2: the remaining cap is UPA determinism, not instance matching

Two engines, two postures.

**Compile-time UPA (`ContentModelDeterminism`)** is now bounded with no silent gap.
The former inlining position automaton (with its `positionCap = 4096` skip) was
replaced on 2026-06-22 by `CompositionalDeterminism`, which summarizes each
`<xs:group>` once and computes `first`/`followlast` over particle identities in
`O(nodes * particles^2)` without inlining, so a multiply-referenced nested group
can no longer blow up to `2^K` positions and is never skipped. The schema-side
expansion is likewise memoized (`GroupParticleMemo`), so the compiled content model
also builds in `O(groups)`, not `2^K`.

**Instance-time matcher (`ContentMatcher`)**, the one that runs on keystrokes, no
longer unrolls occurrences into states. The 2026-06-19 counted matcher stores XSD
occurrence bounds as decimal magnitudes (`NonNegativeDecimal` / `OccurrenceRange`)
and compiles each particle occurrence to a guarded counter loop. That deletes the
old `occursUnrollCap` / `totalStateCap` path and its bounded-to-star widening. The
regression tests now assert exact finite bounds, nested finite bounds, huge finite
upper bounds beyond `Int`, and follow-set behavior before a huge required prefix is
satisfied.

**Why a cap cannot become a bound by tuning.** The blowup is structural: unrolling
encodes an O(log n)-byte numeric bound as n states. No ceiling fixes that without
changing semantics at the ceiling.

**What the remaining proof requires.** The instance matcher now uses a **counting
automaton**: `{m,n}` is represented with a counter/register, not m copies. That
closes the *occurrence*-unrolling blowup. One structural residual remains, distinct
from occurrences:

**Per-instance group-inlining in the NFA build.** `ContentNFABuilder.build`
(ComplexValidator.swift:215, run per validated element) still walks the *inlined*
particle tree, expanding every `<xs:group ref>` in place. A pathological schema
whose nested group references inline to `2^K` positions (e.g. `g{i}=(g{i+1},g{i+1})`)
therefore makes the per-instance **automaton construction** exponential, even though
the *match* over a valid instance keeps a small active set and the compile-time UPA
of the same schema is now polynomial. The trigger is a developer-authored schema,
not external instance data (instance validation against any fixed real schema is
bounded), so the severity is low; but it is where a `2^K`-inlining schema can still
hang on first instance validation. The tree path's NFA build is the cited site; the
streaming path's equivalent term walks (`elementTypes`/`sequenceStructureErrors`,
listed below) share the property. It is recorded here rather than left silent.

The fully general fix is a **pushdown / recursive-transition-network matcher**:
keep group references first-class (`call`/`return` against a stack) so a shared
sub-model is built once (`O(groups)`) with context-pure returns, instead of inlined.
This is pervasive (every `Term` consumer: the NFA builder, the streaming
`elementTypes`/`sequenceStructureErrors`, `wildcardMatch`, `ParticleRestriction`,
completions) and touches the keystroke-critical instance validator, so it is
FP-critical: naive sub-model *sharing* without a stack merges follow sets and is
unsound. It must therefore be gated by a differential that actually exercises deep
group call/return before it can switch. That gate now exists and is hardened: the
streaming-vs-tree differential (`SchemaFuzzTests`) generates a deep **linear**
group-reference chain (`c0 -> … -> c{chainDepth}`, `O(depth)` not `2^depth`, so it
stresses call/return depth without the exponential build) and was run divergence-free
over a 60 000-seed campaign. Until the matcher lands, the residual stands as a
characterized, low-severity, disclosed limitation.

When the pushdown matcher lands behind that gate, Part 2 closes stopper 4 (proven
bounds). The compile-time UPA gap is already closed: `positionCap` was DELETED
(2026-06-22), determinism checked in `O(nodes * particles^2)` with no cap and no
silent skip, proven verdict-equivalent over the whole XSTS corpus.

## If turned into work

- **Part 1:** a per-clause plan for making `ParticleRestriction` exact, each clause
  paired with the FP-guard test matrix (valid restrictions that must still pass)
  before tightening. Drive `invalid-schemas-accepted` / `invalid-instances-accepted`
  to 0 (M2, M3), FP gate sacred.
- **Part 2:** the `ContentMatcher` counter automaton has landed and
  `ContentModelDeterminism.positionCap` is deleted (compile-time UPA now
  polynomial). The remaining acceptance criterion for M4 "proven bounds" is the
  **pushdown / RTN instance matcher** that keeps group references first-class so
  the per-instance NFA build is `O(groups)` not `2^K`, switched only behind the
  hardened deep-group streaming-vs-tree differential (FP gate sacred). Aligns with
  the performance epic (#139, #175–178). The design is pinned in
  `docs/design/counted-content-automaton.md`.
