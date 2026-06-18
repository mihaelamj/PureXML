# Domain First (defer the renderer)

**Status: MANDATORY for any app.** An app does not start with a UI framework. The
first decision is never "this is a SwiftUI app," "this is a UIKit app," or "this
is an AppKit app." That decision is made last, and under the pre-UI layer it need
not be made exclusively at all. The first work is the domain and the business
rules: the entities, their invariants, and the behavior that operates on them, all
framework-free and runnable with no display. The renderer is attached to that, not
the other way around.

## The anti-pattern

Naming the renderer first ("a SwiftUI app") inverts the dependency. It makes the
framework the root of the project and the domain a thing you reach through it, so
business rules end up scattered across view bodies, controllers, and callbacks,
welded to one SDK and untestable without a screen. Every later question (is this
correct, can I reuse this, can I ship it on macOS too) is then blocked behind the
UI you chose before you understood the problem. The renderer is the most
replaceable layer in the system; choosing it first spends your one
feels-irreversible decision on the one part that should have stayed cheap to
change.

## What to start with

The input to this is a clear definition of the business rules and the constraints
that bound them, which external REST services, what compliance, which auth model,
written down first (see `business-rules-and-constraints.md`). Then start with the
domain and the business rules, as the pre-UI layer's two value tiers and three
roles describe (see `ui/pre-ui-layer.md`): Domain (what the
entities are), Surface (display state over them), and the engine that runs every
business rule in response to an enumerable intent vocabulary, reaching I/O only
through injected seams. Build that, prove it headless, and you have an app whose
correctness is established before any pixel exists. The renderer is then a thin
adapter you add at the end.

## Defer the renderer, then pick by behavior

Because the model is renderer-agnostic, the SDK choice is deferred, and it is no
longer forced to be singular. You can develop the SwiftUI, AppKit, and UIKit
renderers over the one model and see which one actually fits a given scenario
better (its animation, accessibility, gesture handling, layout under load,
large-list performance), instead of committing to one on faith at the start. The
renderer becomes an experiment you run late and cheaply, not an assumption you
bake in early. See the renderer section of `ui/pre-ui-layer.md`: the triple render
is both the architecture's payoff and a comparison instrument, one model and
identical behavior underneath, so the framework is the only variable.

## Why this is now a must, not a preference

Two shifts move starting from a formalized domain from tidy to mandatory.

First, the cost of building several renderers has collapsed. Machine
pattern-matching at scale now makes it practical to develop all three Apple UIs
over one model and compare them, work that was too expensive to justify when each
renderer was hand-written from scratch. The deferred, plural renderer choice this
rule asks for is now affordable.

Second, and deeper: that same capability has made tractable, in hours, work that
was prohibitive before. Discovering the latent grammar in a
corpus, naming the possible language it implies, and devising a parser or compiler
for it is now feasible on a timescale that did not exist a few years ago. That
capability rewards a domain already written down as explicit, value-typed,
rule-governed structure, and is nearly blind to one that lives only as scattered
imperative code. A formalized domain (typed entities, named invariants made
unrepresentable or validated as values, an enumerable intent vocabulary,
round-trip laws for every transform) is exactly the structure these tools can
read, check, extend, and translate. So formalizing the domain rules is no longer
optional discipline. In this world it is a must.

## DO

- Begin every app at the domain and the business rules, framework-free and
  headless-provable, before naming any renderer.
- Write the domain down as explicit structure: typed entities, invariants made
  unrepresentable or validated as values (`validation-rules.md`), an enumerable
  intent vocabulary (`ui/pre-ui-layer.md`).
- Treat the renderer as a late, reversible, and plural choice: develop more than
  one and pick by observed behavior.

## DON'T

- Do not open a project by declaring its UI framework ("this is a SwiftUI app");
  the framework is the last decision, not the first.
- Do not put business rules in a view, a controller, or a callback; they belong in
  the framework-free domain and engine.
- Do not leave the domain implicit in imperative code on the promise of formalizing
  it later; formalize it now.

## Acceptance check

A conforming project has: (1) a framework-free domain and engine that build and
pass tests with no UI target present; (2) no business rule reachable only through a
renderer; (3) the renderer named as a late, swappable boundary (one or more),
never as the project's root; and (4) the domain expressed as explicit typed
structure with named, checked invariants, not as imperative code that only a
screen exercises. A project whose first and load-bearing decision is its UI
framework, or whose business rules cannot run without a display, fails this rule.

## Companion rules

- `ui/pre-ui-layer.md`: the two value tiers and three roles this rule starts from;
  the triple render as payoff and comparison instrument.
- `validation-rules.md`: invariants as composable values; every public type
  validated or excluded with a reason.
- `dependency-injection.md`: inject every collaborator, no singletons, so the
  domain stays liftable and testable.
- `parsing-rules.md`, `core/round-trip-transformation.md`, `core/proof-discipline.md`:
  formalizing structure, transforms, and translation claims, the discipline a
  formalized domain makes possible.
