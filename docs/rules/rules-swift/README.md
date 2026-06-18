# Swift coding rules (canonical)

The canonical, scrubbed Swift coding rules. This is the **Swift domain**: the
language- and platform-specific craft of writing Swift well. It sits on top of a
vendored **core spine** of cross-cutting engineering discipline (see
[`core/`](core/)).

Each file here is one Swift rule area. `CONVENTIONS.md` is the short overview; this
repository is the full set, with the cross-cutting discipline vendored under
[`core/`](core/). Examples use a sample tile-based static site generator named
Tiledown (the `TileKit` library plus the `tile-down` executable); replace the
example names with your project's when you adopt these.

## The core spine

The cross-cutting engineering discipline that governs *how* work is done and
reported, independent of language or domain, lives in [`core/`](core/). The Swift
rules here do not duplicate it; they build on it. Read the core spine first:

- `core/no-shortcuts-first-principles.md` - the core ethic: no shortcuts, derive
  from first principles, hold to Knuth's standard of care.
- `core/proof-discipline.md` - framing a correctness claim as separately provable
  layers, each with an explicit epistemic status.
- `core/round-trip-transformation.md` - any two-way transform (parse/print,
  encode/decode) is one invertible description, proven by the round-trip law.
- `core/first-principles-analysis.md` - depth target for analysis, plus
  measurement discipline (every number traceable to a command).
- `core/verification.md` - no "done" without fresh command output.
- `core/testing-discipline.md` - real tests on every change; a build is not a test.
- `core/systematic-debugging.md` - reproduce, isolate, explain, then fix.
- `core/brainstorming.md` and `core/writing-plans.md` - design and planning gates
  before non-trivial work.
- `core/commits.md`, `core/git-discipline.md` - Conventional Commits; issues,
  labels, branches, PRs, remotes.
- `core/file-naming.md`, `core/folder-grouping.md` - filename conventions and when
  to flatten one-file folders.
- `core/rules.md`, `core/self-improve.md` - authoring rules for an agent, and when
  a recurring correction should become one.

## Where an app starts

Before any UI framework is named, an app starts at its business rules and the
domain that enforces them.

- [business-rules-and-constraints.md](business-rules-and-constraints.md) -
  MANDATORY, the first artifact: the business rules written as explicit checkable
  statements, plus the constraints that bound them (which external REST services
  and their contracts, what compliance, which auth model), defined up front.
- [domain-first.md](domain-first.md) - MANDATORY: an app starts at the domain and
  business rules, framework-free and headless-provable; the UI framework is the
  last, reversible, and plural choice, never the first decision.

## Language and platform craft (engine, today)

- [code-style.md](code-style.md) - namespacing discipline, file naming,
  one-type-per-file.
- [namespacing.md](namespacing.md) - caseless `enum` vs `struct` vs `class` for
  namespace anchors.
- [dependency-injection.md](dependency-injection.md) - no singletons, inject every
  collaborator through `init`, protocol seams.
- [concurrency.md](concurrency.md) - Swift 6 strict concurrency: `Sendable`,
  actors, `@MainActor`.
- [cross-platform.md](cross-platform.md) - the same sources build on Apple
  platforms and Linux (and Windows where noted); guard platform-divergent code
  behind a protocol seam.
- [linux-server.md](linux-server.md) - server-side operational rules for the
  `serve` command and any networking.
- [testing.md](testing.md) - Swift Testing, `@Test` / `#expect`, test isolation.
- [formatting-and-linting.md](formatting-and-linting.md) - SwiftFormat and
  SwiftLint, enforced by a pre-commit hook and again in CI.
- [documentation.md](documentation.md) - DocC catalogs and `///` requirements.
- [documentation-search.md](documentation-search.md) - verify API facts against an
  authoritative documentation index, not from memory: query it with keywords and
  read the results for Apple-API facts; it is a search engine, not an agent.
- [framework-policy.md](framework-policy.md) - stay inside Apple's own SDKs and the
  Swift-native ecosystem; Linux falls back to C or C++ only.

## Packages

- [package-structure.md](package-structure.md) - workspace and package layout: one
  `Package.swift` under `Packages/`, many targets, `Apps/` for app targets.
- [package-architecture.md](package-architecture.md) - single-responsibility
  targets with unidirectional dependencies.
- [package-import-contract.md](package-import-contract.md) - per-target allowed
  imports; applies now, the engine and CLI are already two targets.
- [shared-protocols.md](shared-protocols.md) - the cross-target protocol seam.
- [openapi-generated.md](openapi-generated.md) - rules for code generated from an
  OpenAPI document and the hand-written code that surrounds it.

## ExtremePackaging

The granular packaging doctrine lives under [`exp/`](exp/): a monorepo split into
many single-responsibility SPM packages with explicit, unidirectional dependencies,
for isolated compilation, parallel builds, and per-package testability. The two
core files are loaded on every Swift session; the rest load on demand.

- [exp/critical-rules.md](exp/critical-rules.md) - core: the five rules that gate
  every package decision (single responsibility, explicit deps, granularity,
  naming, layer architecture).
- [exp/when-to-create.md](exp/when-to-create.md) - core: the decision tree and
  DO/DON'T list for when a new package is warranted.
- [exp/implementation-patterns.md](exp/implementation-patterns.md) - patterns for
  foundation, feature, middleware, API, component, and font packages, and for
  aggregators.
- [exp/dependency-management.md](exp/dependency-management.md) - cross-package
  dependencies, platform-conditional code, avoiding cycles.
- [exp/package-swift.md](exp/package-swift.md) - the closure-with-local-variables
  pattern for the `deps`, `allProducts`, and `targets` arrays.
- [exp/common-mistakes.md](exp/common-mistakes.md) - anti-patterns paired with the
  canonical fix, for code review of `Package.swift` changes.
- [exp/app-target.md](exp/app-target.md) - adding or modifying an app target
  (SwiftUI, UIKit, AppKit entry points).
- [exp/testing.md](exp/testing.md) - the per-package test target and cross-package
  test doubles (architecture angle; full rules in [testing.md](testing.md)).
- [exp/migration.md](exp/migration.md) - extracting code into a new package or
  splitting a large one.
- [exp/build-performance.md](exp/build-performance.md) - the build-time rationale
  behind the granularity.
- [exp/verification.md](exp/verification.md) - the final checklist before an
  ExtremePackaging change is considered done.

## Parsing and validation

- [parsing-rules.md](parsing-rules.md) - parse first, validate second; the
  OpenAPIKit parsing idiom over any structured input.
- [validation-rules.md](validation-rules.md) - composable `Validation<Subject>`
  values, never imperative if-trees; every public type is validated or excluded
  with a reason, enforced mechanically.

## UI

The UI rules live under [`ui/`](ui/). Any code with UI keeps the renderer thin over a framework-free model, and tests the flows from a shared scenario corpus.

- [ui/pre-ui-layer.md](ui/pre-ui-layer.md) - MANDATORY: all display state and behavior in a framework-free, value-typed model (Domain + Surface); one `perform(Intent)` write channel; renderers are the only UI import, gated mechanically.
- [ui/three-renderers.md](ui/three-renderers.md) - build the same UI in all three Apple SDKs (SwiftUI, UIKit, AppKit) over the one model: the architecture's payoff and a comparison instrument for which framework behaves best in a scenario.
- [ui/swiftui-views.md](ui/swiftui-views.md) - the SwiftUI renderer: view architecture and identity.
- [ui/uikit-views.md](ui/uikit-views.md) - the UIKit renderer: `UIViewController`/`UIView` adapters, diffable data sources, re-pull on the change signal.
- [ui/appkit-views.md](ui/appkit-views.md) - the AppKit renderer: `NSViewController`/`NSView` adapters, `withObservationTracking`, programmatic menus.
- [ui/view-models.md](ui/view-models.md) - view-model responsibilities and patterns.
- [ui/components.md](ui/components.md) - the component system.
- [ui/colors.md](ui/colors.md) - the color system.
- [ui/fonts.md](ui/fonts.md) - font registration in SPM packages.
- [ui/pom.md](ui/pom.md) - Page Object Model for UI tests: screens behind page objects, identifiers from one shared source.
- [ui/flowspec.md](ui/flowspec.md) - declarative UI scenarios driven by [FlowSpec](https://github.com/mihaelamj/FlowSpec): one flow, many renderers, replayed headless and on-device.
