# CLAUDE.md

Guidance for coding agents working in PureXML.

## Project

PureXML is a pure-Swift XML parser/emitter package. It is a root Swift package,
not a monorepo package under `Packages/`.

Non-negotiables:

- no external SwiftPM dependencies
- no C, C++, Objective-C, JavaScript, or generated parser runtime in the public package
- public API under the `PureXML` namespace tree
- macOS, Linux, and WASI build compatibility
- tests for parser and emitter behavior

## Read First

- `AGENTS.md`
- `docs/rules/code-style.md`
- `docs/rules/namespacing.md`
- `docs/rules/cross-platform.md`
- `docs/rules/testing.md`
- `docs/rules/verification.md`
- `docs/production-readiness.md` (the bar for shipping this in an IDE; read every conformance iteration)

Confirm rule loading with `rules-loaded`.

## Commands

```sh
bash scripts/check-style.sh
bash scripts/check-namespacing.sh
swiftformat . --config .swiftformat --lint
swiftlint --config .swiftlint.yml --strict
swift build
swift test
bash scripts/check-wasm.sh
```
