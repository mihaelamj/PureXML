# FlowSpec (declarative UI scenarios)

**Status: RECOMMENDED, and the expected form when a UI ships in more than one renderer.** A UI flow is described once, as a declarative scenario, and replayed against every UI implementation. The scenario is the single source of truth for what a flow does; the implementations cannot drift in their behavior because they all run the same steps. The engine is the public package [FlowSpec](https://github.com/mihaelamj/FlowSpec).

## The model

- A **scenario** is a JSON file: `{ id, title, actor?, preconditions[], tags[], steps[] }`.
- A **step** is `{ verb, target, arg? }`. Its key is `"verb:target"`.
- A **verb** comes from a small closed vocabulary (`open`, `tap`, `type`, `swipe`, `wait`, `assert`, `request`). The vocabulary is deliberately tiny so a scenario reads like a specification, not a script; adding a verb is a coordinated change across the schema, the enum, and every registry.
- A **step registry** is the seam: one per UI, a `@MainActor` type with a single `execute(_ step: Step) throws` that turns a step into a real action against that UI. The registry throws on an unknown `verb:target`, so a scenario can never reference machinery that is not wired up. FlowSpec ships a default identifier-driven XCUITest registry in its `FlowSpecXCUI` module (see `pom.md` for the page-object pattern it drives); the headless registry that drives the model layer you write yourself. The core `FlowSpec` engine stays `Foundation`-only.
- The **runner** walks a scenario's steps in order, stops on the first failure, and reports the scenario id and step index, so a log points at the exact step.

## Why and when

- **One flow, many UIs.** When a feature ships in more than one renderer (SwiftUI, AppKit, UIKit; see `pre-ui-layer.md`), write the flow once and bind a registry per renderer. The renderers cannot disagree about what the flow does, because the steps are shared.
- **The same corpus, headless and on-device.** The engine is `Foundation`-only and transport-agnostic. The same scenario corpus runs on-device through an XCUITest registry that drives page objects (`pom.md`), AND headless through a registry that drives the model layer directly (`pre-ui-layer.md`). This is the strongest form of the pre-UI-layer's headless-parity invariant: do not keep a separate set of hand-written headless tests that can drift from the device scenarios; replay the one corpus both ways.
- **A closed vocabulary keeps scenarios honest.** Because the verb set is small and the registry throws on an unwired step, a scenario stays a readable specification and cannot silently no-op.

## DO

- Keep the flow in a scenario file; keep the per-UI mechanics in a step registry, one per renderer.
- Drive the on-device registry through page objects (`pom.md`), not raw queries.
- Replay the same scenario corpus headless against the model layer; do not fork a separate headless test set.
- Let the runner stop at the first failure and report the scenario id and step index.
- Throw `unknownStep` on an unwired `verb:target` so a scenario cannot reference missing machinery.

## DON'T

- Do not embed UI-framework calls in the scenario or the engine; the engine is `Foundation`-only and the framework binding lives in the registry.
- Do not grow the verb vocabulary casually; a wide verb set turns a scenario back into a script.
- Do not maintain device scenarios and headless tests as two separate corpora that drift; share one.
- Do not let a step silently pass when its handler is missing; the registry throws.

## Acceptance check

A conforming setup has: (1) flows expressed as scenario files, not procedural test code; (2) one `StepRegistry` per renderer, with the UI-framework binding confined to it and the engine `Foundation`-only; (3) the on-device registry driving page objects, not raw element queries; (4) the same scenario corpus replayed headless against the model layer when the UI has a pre-UI layer; (5) an unwired `verb:target` throwing `unknownStep`, verified by a test; (6) failures carrying scenario id and step index. A project that keeps its device scenarios and its headless coverage as two unrelated corpora fails the headless-parity intent of this rule.

## Companion rules

- `pre-ui-layer.md`: the headless registry drives the model layer; one corpus replayed headless and on-device is the strongest headless-parity form.
- `pom.md`: the on-device registry maps each step to a page-object action.
- `../core/testing-discipline.md`: real tests, on every change.
- `../core/no-shortcuts-first-principles.md`: an unwired step throws rather than silently passing.
