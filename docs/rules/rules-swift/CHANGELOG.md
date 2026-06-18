# Changelog

All notable changes to this rule set are documented here. This project follows Semantic Versioning.

## [1.0.0] - 2026-06-15

Initial public release of the Swift domain rules, built on the engineering-discipline core spine (vendored in `core/`).

### Added

- Where an app starts: `business-rules-and-constraints` (MANDATORY first artifact: business rules as explicit checkable statements, plus the constraints that bound them, which REST services, what compliance, which auth model) and `domain-first` (MANDATORY: start at the domain and business rules, framework-free and headless-provable; the UI framework is the last, reversible, and plural choice).
- Swift craft: `code-style`, `namespacing`, `dependency-injection`, `concurrency`, `cross-platform`, `linux-server`, `testing`, `formatting-and-linting`, `documentation`, `documentation-search`, `package-structure`, `package-architecture`, `package-import-contract`, `shared-protocols`.
- UI (`ui/`): `pre-ui-layer` (the display-less model seam, MANDATORY: Domain + Surface, one `perform(Intent)` channel, renderers the only UI import; one model drives the SwiftUI, AppKit, and UIKit renderers at once, both the architecture's payoff and a comparison instrument), `pom` (Page Object Model for UI tests), `flowspec` (declarative UI scenarios via the [FlowSpec](https://github.com/mihaelamj/FlowSpec) package), plus three renderers over the one model (`swiftui-views`, `uikit-views`, `appkit-views`), `view-models`, `components`, `colors`, `fonts`.
- Parsing and validation: `parsing-rules` and `validation-rules` (the OpenAPIKit idiom). Validation requires every public type to be validated or excluded with a reason, enforced mechanically.
- Apple-platform stance: `framework-policy` (Apple-only mandate), `openapi-generated`.
- Drop-in kit: `.gitignore`, `.swiftformat`, `.swiftlint.yml`, `.pre-commit-config.yaml`, and `.githooks/` (a `pre-commit` format-and-lint hook and a `commit-msg` attribution/em-dash check).
- Vendored `core/` spine: the cross-cutting engineering-discipline rules (incl. `round-trip-transformation`).
- Dual license: prose under CC BY 4.0, code under MIT.
