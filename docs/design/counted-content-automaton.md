# Counted content automaton

This is the design for replacing the content-model NFA's occurrence unrolling with
a counted automaton. It is intentionally separate from XSTS conformance fixes:
this work closes the production-readiness resource-bound stopper, not one
schema-validity bucket.

## Problem

`ContentNFABuilder` currently compiles a particle by copying the repeated term
`minOccurs` times and then adding optional copies up to `maxOccurs`. That makes
automaton size proportional to the numeric occurrence value, not to the schema
text. A short schema containing `maxOccurs="1000000000"` can request a billion
states.

The current safety valves are:

- `occursUnrollCap = 16384`
- `totalStateCap = 2^20`
- "degrade to star" when a cap is hit

Those caps prevent OOM, but they change the language. A finite `{m,n}` can become
`{m,unbounded}` or, after an exhausted required prefix, effectively `*`. That is
a silent false negative: invalid instances can pass because the matcher widened a
bounded content model.

`ContentModelDeterminism` has a smaller version of the same issue:
`positionCap = 4096` skips the UPA check when the raw position automaton grows
too large. Skipping a check is bounded as an under-rejection, but it is still
silent debt.

## Sources

Research notes read for this design:

- `/Volumes/Code/DeveloperExt/private/PureXML-research/notes/strange-cases-literature.md`
- `/Volumes/Code/DeveloperExt/private/PureXML-research/notes/xsd-content-model-implementations-survey.md`
- `/Volumes/Code/DeveloperExt/private/PureXML-research/research/scientific-literature.md`

The relevant literature line is:

- Brüggemann-Klein and Wood: UPA is one-unambiguity; the Glushkov position
  automaton is the canonical decision tool.
- Kilpeläinen and Tuhkanen: numeric occurrence indicators make naive
  one-unambiguity algorithms erroneous or exponential; a polynomial method exists.
- Gelade, Gyssens, and Martens: counting separates weak and strong determinism;
  unrolling can be exponentially less succinct than the counted representation.
- Kilpeläinen 2011: the principled XML Schema determinism tool is a counting
  automaton, not occurrence unrolling.

These are witnesses for the algorithm family. PureXML's instance-time matcher now
implements the counted shape against its own `Particle` model; counted UPA remains
separate.

## Correctness claims

Every claim below is labeled per proof discipline.

| Claim | Status | Meaning |
|---|---|---|
| Counted matcher accepts exactly the same child-name language as the XSD particle tree for `element`, `wildcard`, `sequence`, and `choice` with `minOccurs`/`maxOccurs`. | theorem target, implemented | `ContentMatcher.swift` now uses counted configurations; the remaining work is writing the full structural proof against nullable nested particles. |
| Counted matcher keeps per-child matched-particle attribution. | theorem target under UPA, implemented | For UPA-valid content models, each consumed element is matched to exactly one particle; that particle's type/value metadata is the one used by child validation. |
| Counted matcher build size is independent of numeric occurrence magnitudes. | theorem, implemented | `ContentNFABuilder` allocates one counter scope per particle occurrence and a constant number of states/edges per particle; high-bound tests assert state count stays structural. |
| Counted matcher runtime is bounded for interactive validation. | theorem target | For `N` child elements, `S` program states, and `D` counter scopes, validation is bounded by `O(N * S * D)` time and `O(S * D)` live matcher memory. The constants are schema-structural, not occurrence-magnitude structural. |
| `all` groups remain exact. | theorem already implemented, out of scope for NFA replacement | `all` is validated by direct member counts in `ComplexValidator.matchesAll` and `allStructureErrors`; the counted automaton does not need to encode it initially. |
| Counted UPA/determinism replaces `positionCap`. | blocked design frontier | The instance matcher can be replaced first. Deleting `positionCap` requires a separate counted determinism pass or a proof that the existing clamp is exact for XSD's admitted content models. |

## Bound representation

Do not store occurrence bounds as only `Int`.

XSD occurrence values are lexical `nonNegativeInteger`; users can write values
larger than machine integer range. The parser needs an internal representation
that preserves the bound and compares it without overflow:

```swift
enum OccurrenceUpper: Sendable, Equatable {
    case finite(NonNegativeDecimal)
    case unbounded
}

struct OccurrenceRange: Sendable, Equatable {
    var minimum: NonNegativeDecimal
    var maximum: OccurrenceUpper
}
```

`NonNegativeDecimal` is a normalized ASCII decimal string, with leading zeroes
removed except for `0`. It supports:

- equality by string equality;
- ordering by digit count, then lexicographic comparison;
- `isGreaterThan(_ limit: Int)` without constructing a large integer;
- `clamped(to limit: Int) -> Int`, used only when the input length gives a
  semantic cap.

For a concrete instance with `N` child elements:

- any finite upper bound above `N` is equivalent to `N + 1` for rejection/acceptance;
- any minimum above `N` means the model cannot complete after this child list;
- counters never need to hold values above `N + 1`.

That is the key bridge from arbitrary-size lexical numbers to machine-size
runtime counters without changing semantics.

## Program model

Compile the particle tree to a counted epsilon program:

```swift
struct CountedContentProgram: Sendable {
    var states: [State]
    var counters: [CounterScope]
    var start: StateID
    var accept: StateID
}

struct State: Sendable {
    var epsilon: [EpsilonEdge]
    var consuming: ConsumingEdge?
}

struct EpsilonEdge: Sendable {
    var target: StateID
    var guards: [CounterGuard]
    var actions: [CounterAction]
}

struct ConsumingEdge: Sendable {
    var label: TermLabel
    var target: StateID
    var particle: MatchedParticle
}
```

A `CounterScope` belongs to one particle occurrence range. The scope records:

- its `minimum`;
- its `maximum` (`finite` or `unbounded`);
- which nested counters must be reset at the start of each iteration.

The edge language is small:

- `reset(counter)` when entering a repeated particle's scope;
- `increment(counter)` when one iteration of the repeated body completes;
- `counter >= minimum` guard to allow exit;
- `counter < maximum` guard to allow another iteration;
- unconditional epsilon edges for sequence/choice structure.

No operation copies the body `minimum` or `maximum` times.

## Compilation rules

The compiler is structural.

### Element and wildcard

An element or wildcard compiles to one consuming edge. The consuming edge carries
the same `TermLabel` and `MatchedParticle` metadata that `ContentState` carries
today.

### Sequence

Compile each child. Link the previous child's accept state to the next child's
start state with an unconditional epsilon edge. Empty sequence is one epsilon edge
from start to accept.

### Choice

Compile each branch. Add unconditional epsilon edges from the choice start to each
branch start, and from each branch accept to the choice accept.

### Occurrence wrapper

Every particle gets an occurrence wrapper around its term program:

1. On entry, reset the particle counter and every counter nested in its term.
2. If `minimum == 0`, add an exit edge guarded by `counter >= minimum`.
3. If `counter < maximum`, enter the body.
4. On body accept, increment the counter.
5. After increment, either exit when `counter >= minimum` or loop when
   `counter < maximum`.

For `maxOccurs="unbounded"`, the upper guard is always true. For finite maximum,
the guard uses decimal comparison against the current counter value.

The exact one-iteration case `{1,1}` still creates a counter scope initially. A
later optimization may erase scopes whose range is statically `{1,1}`; the proof
does not depend on that optimization.

### Nested occurrence

Nested scopes are reset when their containing scope begins a new iteration. This
is required for models like `(a{2,3}){4,5}`: the inner count is per outer
iteration, not cumulative over the whole match.

This reset relation is computed during compilation by giving each particle term a
set of descendant counter IDs. When an outer scope loops, its entry edge resets
all descendants before the body is entered.

## Runtime algorithm

A runtime configuration is:

```swift
struct Configuration: Hashable {
    var state: StateID
    var counters: CounterStore
}
```

`CounterStore` holds only counters whose value differs from zero. Values are
machine `Int`s clamped to `N + 1`, where `N` is the child-count being validated.

Validation:

1. Compute epsilon closure from the start configuration.
2. For each child name:
   - inspect consuming edges from the current closure;
   - select matching edges by `TermLabel.matches`;
   - emit the matched particle for the chosen edge when the model is UPA-valid;
   - advance to each target configuration;
   - compute epsilon closure again.
3. At the end, accept iff any closed configuration is at the accept state.

Closure applies guards and actions atomically per edge. A guard that fails drops
that edge. An increment above `N + 1` stores `N + 1`; no later decision can
distinguish values above that threshold for a length-`N` input.

## Determinism and attribution

For valid XSD content models, UPA says no input element can be attributed to two
different particles at the same position without lookahead. The counted matcher
should preserve the current API:

- `matchesWhole(_:)`
- `follow(after:)`
- `matchedParticles(_:)`
- incremental `startStates` / `step`

Internally, those APIs become wrappers over counted configurations instead of
plain NFA state sets.

When more than one consuming edge matches a child, that is either:

- an invalid schema that UPA should have rejected; or
- a known UPA under-rejection frontier.

The implementation may keep the current deterministic tie-breaker for recovery
diagnostics, but it must not call that tie-breaker a proof. The proof of
attribution applies only when the content model is UPA-valid.

## Follow sets and completions

`follow(after:)` returns labels available from the current closed configurations.
The counted closure means these labels respect counters exactly:

- after consuming `a` once in `a{1,1}`, `<a>` is not offered again;
- after consuming `a` once in `a{1,2}`, `<a>` is offered once more;
- after consuming `a` twice in `a{1,2}`, `<a>` is no longer offered;
- after consuming fewer than `minOccurs`, completion is false even if the current
  state is structurally close to accept.

This is the visible user-facing benefit for IDE completions: numeric occurrence
diagnostics become exact without unrolling large bounds.

## Resource bound

Let:

- `P` be the number of particle nodes in the compiled content model;
- `S` be the number of counted program states;
- `D` be the number of occurrence scopes/counters;
- `N` be the number of child elements being matched.

Compilation creates a constant number of states and edges per particle and a
constant number of counters per particle:

- `S = O(P)`
- `D = O(P)`
- build memory `O(P)`

During matching, each active configuration has one state and at most `D` live
counter values. For UPA-valid models the closure frontier is bounded by the
program size. Each child step evaluates each reachable consuming edge and closure
edge at most once per distinct reachable configuration after deduplication.

Target bound:

- time `O(N * S * D)`;
- live memory `O(S * D)`;
- counter values bounded by `N + 1`;
- no factor depends on the numeric magnitude of `minOccurs` or `maxOccurs`.

This is the proof obligation the implementation must satisfy before deleting the
current caps.

## Migration plan

1. Done 2026-06-19: add `NonNegativeDecimal`, `OccurrenceUpper`, and `OccurrenceRange` while
   preserving the existing `Particle` API for call sites that only need small
   integer comparisons.
2. Done 2026-06-19: replace `ContentNFABuilder`'s unrolled body copies with a
   counted program behind the existing `ContentNFA` surface.
3. Keep differential tests comparing DTD and XSD matchers on ordinary models
   below the current caps.
4. Done 2026-06-19: add high-bound tests that are exact and previously impossible without language
   widening:
   - `a{2,2}` rejects one `a` and three `a`s;
   - `a{2,100000000000000000000}` accepts two `a`s and rejects one;
   - `a{0,2}` rejects three `a`s;
   - `(a{2,3}){2,2}` accepts four to six `a`s and rejects three/seven;
   - `sequence(a{1000000000000}, b)` never offers `b` before enough `a`s.
5. Done 2026-06-19: switch `ComplexValidatorContentModel`, `XSDCompletions`, and
   `matchedParticles` to the counted program.
6. Done 2026-06-19: delete `occursUnrollCap` and `totalStateCap`.
7. Done 2026-06-19: replace `ContentNFAStateBudgetTests` with exact high-bound tests. The old
   state-ceiling assertion should disappear because there is no state ceiling.
8. Design and land the counted UPA pass; then delete `positionCap`.

## Non-goals for the first implementation slice

- Exact Particle Valid (Restriction) language inclusion. That remains the
  `ParticleRestriction` arc; inclusion for counted regular expressions is a
  different and harder problem.
- Regex counted quantifier replacement. `RegexAutomaton` has the same cap posture,
  but XSD content models are the IDE resource-bound blocker. Regex can reuse the
  counted-bound representation later.
- Changing `all` group semantics. `all` is already matched by counters over its
  members and has XSD-specific occurrence limits.

## Done criteria

This arc is complete only when all are true:

- Done 2026-06-19: `ContentMatcher.swift` contains no `occursUnrollCap`, `totalStateCap`, or
  cap-triggered "degrade to star" path.
- `ContentModelDeterminism.swift` contains no `positionCap` skip.
- Done 2026-06-19: tests include exact high-bound acceptance/rejection cases whose numeric bounds
  exceed any practical unroll count.
- The proof labels in this document are upgraded from "theorem target" to
  "theorem" with code references.
- `docs/release-hurdles.md` no longer lists content-model occurrence unrolling as
  an interactive-safety blocker.

## Counted UPA / deleting `positionCap`: the compositional determinism algorithm

This section specifies the algorithm that deletes `ContentModelDeterminism.positionCap`,
turning the "blocked design frontier" (table row above) into a ready-to-implement,
FP-safe plan. Derived 2026-06-22 from a first-principles analysis of the current engine.

### Why `positionCap` exists (root cause, confirmed in code)

`ContentModelDeterminism` builds a Glushkov position automaton; `groupReference`
(`ContentModelDeterminism.swift`) *inlines* every `<xs:group ref>` via `build(model,…)`,
with the `visiting` set guarding only CYCLES, not repeated references. So
`g0=seq(ref g1, ref g1)`, `g1=seq(ref g2, ref g2)`, … expands to `2^K` positions:
position count is EXPONENTIAL in schema text via multiply-referenced nested groups.
`positionCap = 4096` caps that blowup and, when hit, `return nil` (silently skips the
UPA check = an under-rejection = the remaining stopper-3/4 debt). It is NOT primarily
an overlap-cost issue (`overlap` is O(set²) but within the cap that is ~16M cheap ops,
sub-second at compile time, not a bottleneck): the blocker is the exponential position
COUNT.

### Why naive fixes are unsound

Deduplicating positions by `(label, particle)` so a group's elements get ONE position
regardless of reference count is UNSOUND: a group referenced in context A (followed by
X) and context B (followed by Y) would merge `followpos = X ∪ Y`, manufacturing a
decision set `{X,Y}` that occurs in no single context: a spurious conflict = a FALSE
POSITIVE (violates stopper #1). Inlining is sound precisely because each reference site
gets fresh positions with context-pure `followpos`.

### The sound compositional algorithm (no inlining, bounded O(particles²))

Compute determinism over PARTICLE identities (`ObjectIdentifier` of the element/wildcard
node), of which there are O(schema text size), never over inlined positions. For each
sub-model node compute a summary that is CONTEXT-INDEPENDENT:

- `nullable: Bool`
- `firstParticles: Set<(particle, label)>`: distinct particles that can start it
- `lastParticles: Set<(particle, label)>`: distinct particles that can end it
- `followlast: Set<{particle pair}>`: particle pairs that share a decision set INTERNALLY
  (its own `followpos`-induced co-occurrences), plus the node's internal verdict
- `internalConflict: TermLabel?`: a conflicting label if the sub-model is itself ambiguous

Composition rules (a conflict = two DISTINCT particles whose labels `labelsOverlap`
sharing a decision set):
- leaf (element/`any`): first = last = {(particle,label)}; no internal conflict.
- `choice(c…)`: decision set = ∪ firstParticles(cᵢ); conflict if that set holds a
  distinct-particle overlapping-label pair, or any child conflicts. first/last = unions.
- `sequence(c…)`: walk the nullable runs; at each gap the decision set is the
  firstParticles of the maximal nullable run starting there (joined to the preceding
  run's lastParticles via followpos): check each such set; first = firstParticles of the
  leading nullable prefix; last = lastParticles of the trailing nullable suffix.
- `all(c…)`: every member may follow every other and all share one decision set
  (mirrors the current `all`): the decision set is ∪ firstParticles(cᵢ) AND each member
  pair contributes cross-`followpos`; check the union for conflicts.
- repetition `R{m,n}` with n>1 or unbounded: the Brüggemann-Klein star condition.
  `followlast(R) ∪ firstParticles(R)` must be conflict-free (the last->first repetition
  edge). `{n,n}` clamps to two copies exactly as today (determinism-equivalent); `{0,1}`
  adds no edge.
- `group ref`: use the group's MEMOIZED summary (computed once: context-independent).
  Cross-boundary conflicts (the group's lastParticles followed by the next context's
  firstParticles, and the previous context's lastParticles followed by the group's
  firstParticles) are computed by the PARENT at each reference site, so two distinct
  reference sites never merge their continuations. This is the soundness key: each group
  is summarized once (no `2^K` blowup) while cross-boundary decision sets stay
  context-pure.

Bound: each group summarized once; each composition checks O(particles²) pairs; total
O(nodes × particles²), polynomial in schema text: a PROVEN bound, no cap.

### FP-safe rollout (cardinal rule sacred)

1. Implement the compositional checker ALONGSIDE the existing inlining `violation`; do
   NOT make it authoritative.
2. Add a differential: for every fuzzed schema where `positionCap` is not hit (so the
   inlining oracle is exact) AND for the whole XSTS corpus, assert the compositional
   verdict EQUALS the inlining verdict. Extend `SchemaGenerator` to emphasize
   multiply-referenced nested groups.
3. Iterate the compositional checker until it agrees everywhere (the inlining check is
   the trusted oracle; any divergence is a bug in the new checker, fixed toward
   agreement). This makes the change FP-safe by construction: nothing ships until proven
   equivalent on the oracle.
4. Only then switch `violation` to the compositional checker and DELETE `positionCap`.
   Add a perf test on the `2^K`-group pattern proving polynomial (not exponential) time.

### Acceptance criteria (supersedes the `positionCap` row in the table above)

- `ContentModelDeterminism.swift` contains no `positionCap` and no silent UPA skip.
- The compositional/inlining differential passes on XSTS + a deep group-ref fuzz.
- A perf test compiles a `2^K`-nested-group schema (K ≥ 20) within a tight time bound.
- XSTS `valid-schemas-rejected` stays 0 and `invalid-schemas-accepted` does not rise
  (it may fall, as previously-skipped pathological models now get checked).
