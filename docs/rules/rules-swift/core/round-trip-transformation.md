# Round-Trip Transformation Rules (MANDATORY)

When you build a **bidirectional transformation** (parse and print, decode and
encode, decompile and compile, deserialize and serialize, lower and lift) you
**MUST** make the two directions a single invertible description, not a parser
and a printer written separately and hoped to agree. This rule governs the layer
where text and model convert *both ways*, the step after parse and before
validate. It is the companion to `proof-discipline.md`: the round-trip law is a
theorem you prove, not a hope.

## Reference

Invertible syntax descriptions (Rendel and Ostermann, 2010) and lenses (Foster et
al., 2007). In Swift the canonical tool is Point-Free `swift-parsing`'s
`ParserPrinter`; when a dependency is unwanted, a minimal `Conversion`-based core
(below) delivers the same guarantee.

## The law comes first (state it before any grammar)

Before writing a single rule of the surface, state the round-trip law and pick
the smallest provable slice. The laws, named after the lens laws:

- **Λ1 (GetPut)**: `parse(print(x)) == x` for every model value `x`. The surface
  loses nothing the model holds.
- **Λ2 (idempotence)**: `print(parse(s)) == s` for every `s` in the printer's
  **normal form**. Idempotence is asked of the tool's own output, never of an
  arbitrary author's spacing.
- **Λ3 (inherited exactness)**: when this edge sits on another that is already
  exact (a model that round-trips to bytes), the whole composition is exact the
  moment Λ1 holds. Inherit the proof; do not repeat it.

No grammar is declared complete before its round trip is green over real data.
Completeness is a proof, not a feeling.

## By construction, not by hope (the core requirement)

A bidirectional transform built as two independent functions is wrong even when
the tests pass: nothing prevents them drifting. Build instead from an **invertible
algebra**, where every primitive defines its forward and backward together and
composition preserves invertibility:

- **A leaf encoder is honestly invertible.** If you quote, you escape on print and
  unescape on parse, so the law holds for *every* value, not only the benign ones
  your corpus happens to contain. "It works on our data" is corpus luck, not
  soundness; state and enforce the precondition or remove it.
- **`map` goes through a `Conversion` (a partial isomorphism)**, not a one-way
  function. Forward (`apply`) may reject an invalid surface; backward (`unapply`)
  is total, since every model value has a surface. A plain `(A) -> B` map is not
  invertible and breaks the guarantee immediately.
- **`zip` / `oneOf` / `many` / `optional`** sequence, choose, repeat, and skip
  while keeping both directions in lockstep. Express structure with these, not with
  a hand-written recursive descent paired with a hand-written emitter.

The minimal Swift core when not adopting `swift-parsing`:

```swift
struct ParserPrinter<Value> {
    let parse: (inout Substring) -> Value?   // consume a prefix, yield a value
    let print: (Value) -> String             // render a value
}
struct Conversion<A, B> {
    let apply: (A) -> B?    // forward, may reject
    let unapply: (B) -> A   // backward, total
}
// map(_:_:), zip(_:_:), optional(_:), many(_:), oneOf(_:), terminated(_:by:), literal(_:)
```

## The gate (the witness, not the proof)

The by-construction algebra is the proof; a **round-trip test over real data is its
witness**. Gate every slice with: for each value in the corpus, `parse(print(v))`
recovers `v` (Λ1) and `print(parse(s))` is idempotent (Λ2). Also test, as pure
cases, that a malformed surface is **rejected** (returns nil), not silently
corrupted, and that the awkward leaf values (embedded quotes, escapes, empty,
whitespace) round-trip. Grow the surface one construct at a time, each keeping the
gate green, exactly as a typed model grows one field at a time.

But a green corpus gate certifies the corpus, not the construction. The corpus is
a sample; it contains the values someone happened to author, not the values the
model can represent. So every slice owes a second, **adversarial** pass that the
corpus cannot give: hunt for a **reachable model value with no surface**, a value
the type can hold and the projection can produce, for which `print` traps, force
unwraps, force-indexes an empty collection, or emits a surface that does not parse
back. The empty collection is the classic one: a `[String: [String: String]]` can
hold `["owner": [:]]`, an array-backed list can be empty, an optional-of-list can
be `.some([])`. If `print` is partial on any such value, the transform is partial
without a stated precondition, and the rule is violated even though the corpus is
green. The fix is always one of two shapes: make `print` **total** (the empty list
prints to nothing, never traps), and make the degenerate value **unrepresentable
in the normal form** (normalize it away, the absent-equals-empty idiom), so it can
neither force an empty wrapper nor crash. Pin the adversarial value as a passing
regression. Prefer an actual adversarial reader (a second person, or a subagent
critic that builds an executable harness and drives hostile values) over your own
reread: the author who built the construction is the worst auditor of it.

## DO

- State the round-trip law and the smallest slice before writing the grammar.
- Build both directions from one invertible description (a `ParserPrinter`).
- Make leaf encoders honestly invertible (escape and unescape); never rely on the
  corpus being benign.
- Use a `Conversion`/partial-isomorphism for `map`; never a one-way function.
- Compose with `zip` / `oneOf` / `many` / `optional`, not hand-rolled descent.
- Gate every slice with a corpus round trip plus rejection and awkward-value cases.
- Make `print` total: every reachable model value has a surface. No force-unwrap,
  no force-index of a possibly-empty collection, on the print side.
- Run an adversarial-construction pass per slice, separate from the corpus gate:
  find a reachable value with no surface; if one exists, make print total and
  normalize the degenerate value away, then pin it as a regression.
- Inherit exactness from a lower edge that is already proven; do not re-prove it.

## DON'T

- Do not write a parser and a printer separately and trust that they agree.
- Do not declare the round trip correct because the corpus passes; corpus-benign
  is not invertible, and a corpus gate cannot find a reachable value the corpus
  does not contain. Let an adversarial reader certify the construction.
- Do not leave `print` partial: a force-index or force-unwrap that traps on an
  empty collection is a reachable value with no surface, not an edge case.
- Do not phrase `print` as a one-way render with a separately maintained `parse`.
- Do not grow the grammar on ad-hoc combinators that cannot compose into the
  recursive, nested, heterogeneous structures the real format needs.

## Acceptance check

A repo with a bidirectional transform conforms when: (1) the round-trip law is
stated (in the design doc) before the grammar; (2) both directions derive from one
`ParserPrinter`-style description, and `map` uses a `Conversion`, not a one-way
function (grep finds the invertible algebra, not a standalone hand-written
emitter); (3) leaf encoders escape/unescape so Λ1 holds for all values; (4) a
corpus round-trip gate is green, with explicit rejection and awkward-value cases;
and (5) `print` is total over reachable model values, verified by an adversarial
pass that hunts a value with no surface, not by the corpus alone, with any such
value normalized away and pinned as a regression. A transform whose two directions
are independent functions fails this rule even if its tests currently pass; so
does one whose `print` traps on a reachable empty collection that the corpus
happens not to contain.
