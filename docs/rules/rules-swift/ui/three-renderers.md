# Three Renderers (one model, all three Apple SDKs)

**Status: the standing UI aspiration, pursued whenever bandwidth allows.** Build the
same UI in all three Apple SDKs, SwiftUI, UIKit, and AppKit, over the one
framework-free model (see `pre-ui-layer.md`). The model is renderer-agnostic by
construction, so attaching a second and a third renderer is additive, not a
rewrite. A model that only ever drives one renderer is leaving the architecture's
central guarantee unused.

## Why build all three

1. **It is the payoff, not an afterthought.** The pre-UI layer exists so behavior
   lives in a value-typed model and the renderer is a thin adapter. Once that holds,
   three idioms over one behavior, proven identical by the same headless corpus, is
   exactly what the discipline was for.
2. **It is a comparison instrument.** With one model and identical behavior
   underneath, the renderer is the only variable. Building the same surface in each
   SDK turns "which framework behaves best here" into an apples-to-apples test
   rather than a guess: animation smoothness, accessibility, gesture handling,
   layout under load, large-list performance. Reach for it whenever a scenario's UI
   behavior is uncertain.
3. **The cost has collapsed.** Machine pattern-matching at scale now makes
   developing several renderers affordable, where hand-writing each from scratch was
   once too expensive to justify.

## What this requires

- One framework-free model: Domain plus Surface, a single `perform(_ intent:)`
  write channel, and a `Set<SurfaceArea>` change signal (see `pre-ui-layer.md`).
- Each renderer a thin adapter that reads surfaces, forwards intents, and
  re-renders on the signal: SwiftUI via Observation, AppKit via
  `withObservationTracking`, UIKit via a re-pull loop. The renderers hold no
  behavior worth testing.
- One shared ordered scenario corpus replayed headless and on-device, so the three
  renderers cannot disagree about what the UI does (see `flowspec.md`).

## Three is the aspiration, not a tax on every screen

Build the renderer your product ships first; add the others when bandwidth allows,
or when a scenario's behavior is genuinely in question and you want the comparison.
Never let "only one renderer for now" leak behavior into that renderer: the model
stays complete and renderer-agnostic no matter how many adapters exist today, which
is exactly what keeps the second and third cheap to add later. The decision is
deferred and reversible (see `domain-first.md`), never baked into the model.

## Acceptance check

A codebase honoring this rule has: (1) a framework-free model that builds and tests
headless with no renderer attached; (2) at least one renderer as a thin adapter
over that model, with a clear, additive path to a second and third because no
behavior lives in the renderer; and (3) where more than one renderer exists, a
single shared scenario corpus they are all proven against. A codebase whose single
renderer owns behavior, so a second renderer would mean reimplementing logic rather
than adding an adapter, fails this rule even if it ships.

## Companion rules

- `pre-ui-layer.md`: the framework-free model the renderers share; its renderer
  section states this triple-render aspiration in architectural context.
- `domain-first.md`: defer the renderer choice, then develop more than one and pick
  by observed behavior.
- `flowspec.md`: one flow, many renderers, replayed headless and on-device.
