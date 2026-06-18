# Proof Discipline for Correctness Claims (MANDATORY)

When a system claims to **translate, compile, encode, render, or compute** a
result that is supposed to match a specification or a reference (a format
importer, a codec, a converter, a layout or render engine, any "X in yields the
correct Y out") you **MUST** frame the correctness claim as a set of separately
provable sub-claims, each carrying an explicit epistemic status, and you **MUST**
distinguish what is proven from what is merely witnessed or still open. "It works"
is not a claim; it is the absence of one. This is the companion to
`no-shortcuts-first-principles.md` (disclosed limits, never hidden debt) and to
`round-trip-transformation.md`, which governs the special case of an invertible
transform.

## Reference

The pattern is Knuth's standard restated: correctness is total over enumerated
cases, never "works on the input I tried." It is the proof-versus-witness
distinction from formal methods (a model checker's counterexample is a witness;
the invariant is the theorem) and the oracle problem from testing theory: the
thing you compare against may itself be wrong.

## Decompose the claim before proving anything

"This system is correct" is not one claim; it is several, and they have different
provability. Name the layers first, then prove each on its own terms. A typical
input-to-output pipeline decomposes into something like:

- **Read**: every element the input format defines is either modeled or
  reported; the decode is total over malformed input. (Provable as a theorem.)
- **Map or report**: every feature is handled correctly OR collected into a
  report; never silently handled wrong. (Provable as a partition theorem.)
- **Numeric computation**: geometry, transforms, arithmetic match closed-form
  values to floating-point epsilon. (Provable as a theorem; sampled quantities
  carry a measured bound.)
- **Output equivalence**: the final artifact (pixels, bytes, layout) matches a
  golden. (Often NOT provable without tooling; name it as a frontier.)

Your pipeline may have different layers; the point is that they are distinct
claims of distinct strength. A system that asserts the strong claim ("correct")
while only the weak claims are proven is violating this rule even if every test is
green.

## Every claim carries an explicit status label

No claim ships unlabeled. Tag each in the artifact (test name, doc, issue) with
exactly one:

- **theorem**: proven by construction or closed form, over all cases, both
  directions where applicable.
- **theorem (bounded to N)**: a theorem relative to a pinned reference (a spec at
  a commit); state the bound.
- **sampled**: verified at a sample grid with a **measured** error bound (record
  the bound and how it was derived), never an assumed one.
- **witnessed**: corroborated by an external reference that is itself fallible
  (see below). Not proof.
- **assumed**: taken on faith; a debt, must be tracked.
- **blocked (with reason)**: cannot currently be proven; name the blocker.

"Now measured, not assumed" is the upgrade you are always trying to make: turn an
`assumed` into a `sampled` with a real bound, or a `witnessed` into a `theorem`.

## The reference is a witness, not the ground truth

When you check output against an external implementation (a vendor renderer, a
reference codec, another library's result), that implementation is a
**corroborating witness, not the oracle**. The ground truth is the spec and the
closed form. When your closed-form result and the reference disagree, the
reference is the anomaly to **explain**, not the authority to obey: a reference
that computes a result differently from the spec's closed form is the one in
error, and a test that pins "we match the closed form, and the reference happens
to agree" is stronger than one that pins "we match the reference." Demote the
reference in writing; never let a fallible implementation stand in as ground
truth.

## No silent mismatch: classify every case exactly once

Every input feature is **handled correctly or reported as unsupported**, never
silently handled wrong, never dropped without a trace. The report is part of the
output. Loss is explicit and complete: every case is classified exactly once, zero
silent mismatches, and the loss counts are **re-derived live from the report** so
they cannot drift from the code. A feature you cannot handle (an input variant
with no decoder, an operation the backend lacks) is **reported, not faked**.
Faking it, producing a plausible-looking wrong result and staying silent, is the
cardinal sin this rule exists to forbid.

## Name the unproven frontier, with its reason

The claim you cannot prove gets named explicitly, with the blocker and any partial
instrument, in the same place the proven claims live. For example, final-output
equivalence may be `blocked` because no programmatic reference exists to compare
against; a partial analytic oracle that covers the simple, closed-form cases is
the partial instrument; the path to closure is named. This is the difference
between **open-by-named-frontier** (required) and **open-by-omission** (forbidden,
a hidden gap under `no-shortcuts-first-principles.md`). A reader must be able to
see, in the artifact, exactly which claim is unproven and why.

## DO

- Decompose the correctness claim into separately provable layers before writing
  any verification.
- Label every claim with one status (theorem / bounded / sampled / witnessed /
  assumed / blocked-with-reason); never ship an unlabeled "correct."
- Prove what is provable as a theorem (closed form, both directions); for sampled
  quantities, record a measured error bound, not an assumed one.
- Treat any external reference as a fallible witness; pin tests to the closed form
  and note that the reference merely agrees.
- Emit a report for every unsupported feature; make it part of the output;
  re-derive loss counts live from the report.
- Name the unproven frontier with its blocker and partial instrument, in the
  artifact, next to the proven claims.

## DON'T

- Do not collapse several claims of different strength into one undifferentiated
  "it works."
- Do not let an external reference be the ground truth; do not pin "we match
  <implementation>" as if that implementation were infallible.
- Do not silently produce a wrong result for an unsupported feature, or drop it
  without a trace. Report it.
- Do not assume an error bound; measure it. A round-number tolerance with no
  derivation is an invented number (see `first-principles-analysis.md`).
- Do not leave a gap open by omission. An unnamed unproven claim reads as proven
  and is a hidden debt.

## Acceptance check

A system that claims correctness conforms when: (1) the claim is decomposed into
named layers, each independently verified; (2) every claim in the docs/tests
carries one status label, with no bare "correct"; (3) unsupported features are
reported through a report object that is part of the output, and a grep finds no
silent normal-path fallback for a feature the backend cannot do; (4) tests pin
closed-form / analytic ground truth, with any external reference named a witness,
not the oracle; (5) sampled claims record a measured bound, not a round-number
assumption; and (6) every unproven claim is named in the artifact with its blocker
and any partial instrument. A system that asserts "correct" while only its weakest
layers are proven, or that pins an external implementation as ground truth, or
that silently produces a wrong result for an unsupported feature, fails this rule
even if its suite is green.

## Companion rules

- `no-shortcuts-first-principles.md`: the ethic this specializes. Disclosed limits
  are fine, hidden debt is the violation; total correctness over enumerated cases.
- `round-trip-transformation.md`: the by-construction cousin for invertible
  transforms (the round-trip law is itself a theorem; this rule generalizes it to
  non-invertible translation and computation).
- `first-principles-analysis.md`: measurement discipline. The claim-tagging this
  rule's `sampled` / measured labels inherit (MEASURED / DERIVED / RANGED /
  STRUCTURAL / DOCUMENTED).
- `validation-rules.md`: validate after parse; the report this rule requires is
  where validation failures land.
- `testing-discipline.md` and `verification.md`: run the
  suite, cite counts, before claiming a layer proven.

## Why this exists

"It works" routinely masks an unproven output-equivalence claim hiding behind
proven coverage and numeric claims. This rule separates what can be proven as a
theorem (coverage, numeric exactness, complete loss accounting) from what is only
corroborated by a fallible reference, and from what remains a named,
tooling-blocked frontier, so the strength of every claim is legible in the
artifact rather than collapsed into a single optimistic "correct." It is portable
to any translator, compiler, codec, or layout engine.
