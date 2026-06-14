# PureXML Rules

Load these rules before changing code:

- `code-style.md`
- `namespacing.md`
- `cross-platform.md`
- `testing.md`
- `verification.md`
- `commits.md`
- `research-first.md`

Project-specific overrides:

- PureXML uses a root `Package.swift`.
- Sources live directly under `Sources`.
- Tests live in `Tests` (test target `PureXMLTests`).
- `Package.swift` must keep `dependencies: []`.
- Public API must live under the `PureXML` namespace tree.
- The package must build on macOS, Linux, Windows, and WASI.

The broader rule files are retained for detailed guidance. When they include
generic examples, apply the PureXML-specific overrides above.
