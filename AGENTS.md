# Agent Guide

Guidance for anyone writing code in PureXML.

## Rule Loading

At the start of a session, read this file and the rules under `docs/rules/` that
match the task. Confirm by replying with `rules-loaded` and name the files you
loaded.

For code changes, load at minimum:

- `docs/rules/code-style.md`
- `docs/rules/namespacing.md`
- `docs/rules/cross-platform.md`
- `docs/rules/testing.md`
- `docs/rules/verification.md`
- `docs/rules/commits.md`

## What PureXML Is

PureXML is a dependency-free XML package written entirely in Swift.

The package must stay:

- pure Swift
- root Swift package layout, with `Package.swift` at repository root
- dependency-free
- Linux-compatible
- WebAssembly/WASI-compatible
- namespaced under `PureXML`

The private `PureXMLResearch` repo is for studying reference XML implementations
(libxml2/`expat`, Foundation's `XMLParser`, and the W3C XML 1.0 conformance
suite). Do not copy C code or upstream parser source into this public package.
Keep attribution in `ATTRIBUTION.md` accurate when compatibility work references
those projects.

Compatibility work must start from that research source. Before changing parser,
emitter, validation, or typed conversion behavior, inspect the matching
PureXMLResearch source or fixture and use it only to define behavior and tests.

## Namespace Rules

Every public type lives under the `PureXML` namespace tree and mirrors its
folder:

- `Sources/Model/Node.swift` declares `PureXML.Model.Node`
- `Sources/Parsing/Parser.swift` declares `PureXML.Parsing.Parser`
- `Sources/Emitting/Serializer.swift` declares `PureXML.Emitting.Serializer`
- `Sources/Validation/Validator.swift` declares `PureXML.Validation.Validator`

No top-level public concrete types except the root `public enum PureXML`.

## Dependency Rules

`Package.swift` must keep `dependencies: []`.

Do not add external packages, C targets, system libraries, Foundation-only
workarounds, JavaScript tooling, or generated parser dependencies without an
explicit maintainer decision.

## Verification

Before claiming a change is complete, run and cite:

```sh
bash scripts/check-style.sh
bash scripts/check-namespacing.sh
bash scripts/check-forbidden-patterns.sh
swiftformat . --config .swiftformat --lint
swiftlint --config .swiftlint.yml --strict
swift build
swift test
bash scripts/check-wasm.sh
```

Enable local hooks:

```sh
git config core.hooksPath .githooks
```
