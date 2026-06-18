# Release hurdles to 1.0 (analysis)

Companion to [`production-readiness.md`](production-readiness.md) (the four
stoppers) and [`roadmap.md`](roadmap.md) (milestones). This characterizes, with
evidence, what actually stands between the current engine and a 1.0 fit to put in
front of a developer as the authority on XML/XSD correctness.

Snapshot at time of writing: v0.2.0 released; full 2006-11-06 XSTS archive (14383
groups) with `valid-schemas-rejected = 0`, `invalid-schemas-accepted = 46`,
`valid-instances-rejected = 0`, `invalid-instances-accepted = 31`.

## Status against the four stoppers

1. **Rejecting valid input (false positives).** `valid-schemas-rejected = 0` and
   `valid-instances-rejected = 0` on the **full** XSTS archive, corroborated by the
   libxml2 differential over 9618 schemas. **Met.** This is the doc's bar to be "an
   authority"; it is cleared on the measured corpora.
2. **Silently accepting faulty input (false negatives).** `invalid-schemas-accepted
   = 46`, `invalid-instances-accepted = 31`. **Not at 0.** This is the bulk of named
   milestone work (M2, M3) and the subject of Part 1 below.
3. **Uncharacterized correctness.** Differential harness vs libxml2 and a fuzz
   suite exist (M1, ~done). Gap: real-world corpora beyond XSTS, and the silent
   under-rejections noted in Part 2.
4. **Interactive safety.** Located diagnostics (#169) done; validation reports all
   errors (recoverable). Gap: a *proven* worst-case time/memory bound. The engine
   uses caps, which the standard explicitly disqualifies ("a cap is a band-aid, not
   a bound"). Subject of Part 2.

## The biggest hurdle, stated plainly

Driving the false-negative buckets (`invalid-schemas-accepted = 46`,
`invalid-instances-accepted = 31`) to zero is the largest remaining body of named
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
| elemZ026/027/028 | element-decl restriction where base is a substitution-group head | not modelled |
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

## Part 2: the caps are band-aids because matching unrolls occurrence values, not text

Two engines, two postures.

**Compile-time UPA (`ContentModelDeterminism`)** is fairly safe: it clamps `{n,n}`
to 2 copies and uses a self-loop for repetition (ContentModelDeterminism.swift:117–132),
so positions ≈ schema *text* size. `positionCap = 4096` is a backstop for
pathological nested group references; when hit it **silently skips the UPA check**
(`return nil`, ContentModelDeterminism.swift:85): a hidden false negative and a
stopper-3 silent gap, but rare.

**Instance-time matcher (`ContentMatcher`)**, the one that runs on keystrokes, is
the real problem. It builds the NFA by **unrolling** occurrences into states
(`for _ in 0..<boundedMin { … addState() }`, ContentMatcher.swift:203–208), so NFA
size is proportional to the **numeric value** of the occurrence bound, not the
schema text: `maxOccurs="1000000000"` is 10 bytes that want a billion states. The
caps (`occursUnrollCap = 16384` per particle, `totalStateCap = 2²⁰` total) clip it,
but on hitting the ceiling the repetition **"degrades to star"** (treats a bounded
`{m,n}` as unbounded → accepts content it should reject, a false negative;
ContentMatcher.swift:211–214). This OOM-killed the suite at 8 GB before the cap
(#129).

**Why a cap cannot become a bound by tuning.** The blowup is structural: unrolling
encodes an O(log n)-byte numeric bound as n states. No ceiling fixes that without
changing semantics at the ceiling.

**What an actual proof requires.** Replace unroll-into-states with a **counting
automaton**: represent `{m,n}` with a counter/register, not m copies. Then:

- build size = O(schema text size), independent of the numeric bounds;
- instance matching = O(input length × schema size), counter values bounded by the
  log-encoded bounds → polynomial, no blowup;
- determinism-with-counters is decidable in polynomial time (Gelade–Martens–Neven /
  Kilpeläinen–Tuhkanen line on regexes with numeric occurrence constraints).

That yields a provable worst-case time/space bound, removes **all** the caps, and
closes the silent star-degradation and the `positionCap` skip. Stopper 4 (proven
bounds) and stopper 3 (no silent debt) are the same fix here. It is a
re-architecture of the matcher core, not a tweak, which is what makes it
foundational rather than incremental.

## If turned into work

- **Part 1:** a per-clause plan for making `ParticleRestriction` exact, each clause
  paired with the FP-guard test matrix (valid restrictions that must still pass)
  before tightening. Drive `invalid-schemas-accepted` / `invalid-instances-accepted`
  to 0 (M2, M3), FP gate sacred.
- **Part 2:** a counter-automaton design for `ContentMatcher` (and the determinism
  automaton), with acceptance criteria = the `occursUnrollCap` / `totalStateCap` /
  `positionCap` caps deleted and a stated worst-case bound, no silent star-degradation
  (M4 "proven bounds"). Aligns with the performance epic (#139, #175–178).
